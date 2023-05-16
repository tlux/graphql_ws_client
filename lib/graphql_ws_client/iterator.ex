defmodule GraphQLWSClient.Iterator do
  @moduledoc false

  use GenServer

  require Logger

  alias GraphQLWSClient.Event
  alias GraphQLWSClient.Iterator.{Opts, State}

  @type iterator :: GenServer.server()

  @spec start_link(Opts.valid()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
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
      |> Keyword.merge(client: client, query: query, variables: variables)
      |> Opts.new()
      |> Opts.validate!()

    {:ok, iterator} = start_link(opts)
    iterator
  end

  @spec close(iterator) :: :ok
  def close(iterator) do
    GenServer.stop(iterator)
  end

  @spec next(iterator) :: [any] | :halt
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
    monitor_ref = Process.monitor(opts.client)

    subscription_id =
      GraphQLWSClient.subscribe!(opts.client, opts.query, opts.variables)

    {:ok,
     %State{
       buffer_size: opts.buffer_size,
       client: opts.client,
       monitor_ref: monitor_ref,
       subscription_id: subscription_id
     }}
  end

  @impl true
  def terminate(_reason, %State{} = state) do
    Process.demonitor(state.monitor_ref)

    if state.subscription_id do
      GraphQLWSClient.unsubscribe(state.client, state.subscription_id)
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
    {:reply, Enum.reverse(state.buffer), %{state | buffer: [], from: nil}}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %State{monitor_ref: ref} = state
      ) do
    {:stop, :closed, halt(state)}
  end

  def handle_info(%Event{type: :complete}, %State{} = state) do
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
    GenServer.reply(state.from, Enum.reverse([payload | state.buffer]))
    {:noreply, %{state | buffer: [], from: nil}}
  end

  def handle_info(%Event{type: :error, payload: error}, %State{} = state) do
    {:stop, {:error, error}, state}
  end

  # Helpers

  defp halt(state) do
    if state.from do
      buffer = if state.buffer == [], do: :halt, else: state.buffer
      GenServer.reply(state.from, buffer)
    end

    %{state | from: nil, halted?: true, subscription_id: nil}
  end

  defp truncate_buffer(list, :infinity), do: list

  defp truncate_buffer(list, size), do: Enum.take(list, size)
end
