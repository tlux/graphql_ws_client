defmodule GraphQLWSClient.Iterator do
  @moduledoc false

  use GenServer

  require Logger

  import GraphQLWSClient.FormatLog

  alias GraphQLWSClient.Event
  alias GraphQLWSClient.Iterator.{Opts, State}

  @type iterator :: GenServer.server()

  @spec start_link(Opts.valid()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec start(Opts.valid()) :: GenServer.on_start()
  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

  @spec open!(
          GraphQLWSClient.client(),
          GraphQLWSClient.query(),
          GraphQLWSClient.variables(),
          Keyword.t()
        ) :: iterator | no_return
  def open!(client, query, variables \\ %{}, opts \\ []) do
    opts =
      opts
      |> Keyword.merge(
        client: client,
        query: query,
        variables: variables
      )
      |> Opts.new()
      |> Opts.validate!()

    {:ok, iterator} = start_link(opts)
    iterator
  end

  @spec close(iterator) :: :ok
  def close(iterator) do
    GenServer.stop(iterator)
  end

  @spec next(iterator) :: {:ok, [any]} | {:error, Exception.t()} | :halt
  def next(iterator) do
    GenServer.call(iterator, :next, :infinity)
  end

  @spec child_spec(term) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  # Callbacks

  @impl true
  def init(%Opts{} = opts) do
    Process.flag(:trap_exit, true)

    case GraphQLWSClient.subscribe(opts.client, opts.query, opts.variables) do
      {:ok, subscription_id} ->
        {:ok,
         %State{
           buffer_size: opts.buffer_size,
           client: opts.client,
           monitor_ref: Process.monitor(opts.client),
           subscription_id: subscription_id
         }}

      {:error, error} ->
        {:stop, error}
    end
  end

  @impl true
  def terminate(_reason, %State{
        client: client,
        monitor_ref: monitor_ref,
        subscription_id: subscription_id
      }) do
    if monitor_ref do
      Process.demonitor(monitor_ref, [:flush])
    end

    if subscription_id do
      GraphQLWSClient.unsubscribe(client, subscription_id)
    end
  end

  @impl true
  def handle_call(:next, _from, %State{halted?: true, buffer: []} = state) do
    {:reply, :halt, state}
  end

  def handle_call(:next, from, %State{buffer: []} = state) do
    {:noreply, %{state | from: from}}
  end

  def handle_call(:next, _from, %State{} = state) do
    {:reply, {:ok, Enum.reverse(state.buffer)},
     %{state | buffer: [], from: nil}}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %State{monitor_ref: ref} = state
      ) do
    {:noreply, halt_and_reply(state)}
  end

  def handle_info(%Event{type: :complete}, %State{} = state) do
    {:noreply, halt_and_reply(state)}
  end

  def handle_info(%Event{type: :error, payload: error}, %State{} = state) do
    Logger.error(format_log("Iteration halted: #{Exception.message(error)}"))
    GenServer.reply(state.from, {:error, error})
    {:noreply, halt(state)}
  end

  def handle_info(
        %Event{type: :next, payload: payload},
        %State{from: nil} = state
      ) do
    buffer = truncate_buffer([payload | state.buffer], state.buffer_size)
    {:noreply, %{state | buffer: buffer}}
  end

  def handle_info(%Event{type: :next, payload: payload}, %State{} = state) do
    GenServer.reply(state.from, {:ok, Enum.reverse([payload | state.buffer])})
    {:noreply, %{state | buffer: [], from: nil}}
  end

  # Helpers

  defp halt(state) do
    %{state | from: nil, halted?: true, subscription_id: nil}
  end

  defp halt_and_reply(state) do
    if state.from do
      reply =
        case state.buffer do
          [] -> :halt
          buffer -> {:ok, buffer}
        end

      GenServer.reply(state.from, reply)
    end

    halt(state)
  end

  defp truncate_buffer(list, :infinity), do: list

  defp truncate_buffer(list, size), do: Enum.take(list, size)
end
