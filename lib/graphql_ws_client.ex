defmodule GraphQLWSClient do
  use Connection

  require Logger

  alias GraphQLWSClient.{Config, Options, State}

  @type client :: GenServer.server()

  @spec start_link(Keyword.t() | GenServer.options()) :: GenServer.on_start()
  def start_link(opts) do
    {init_opts, opts} =
      Keyword.split(
        opts,
        [:url | Map.keys(Options.__struct__())]
      )

    start_link(init_opts, opts)
  end

  @spec start_link(Keyword.t() | map, GenServer.options()) ::
          GenServer.on_start()
  def start_link(init_opts, opts) do
    Connection.start_link(__MODULE__, Options.new(init_opts), opts)
  end

  @spec close(client) :: :ok
  def close(client) do
    Connection.call(client, :close)
  end

  @spec query(client, String.t(), map) :: {:ok, any} | {:error, term}
  def query(client, query, variables \\ %{}) do
    with {:ok, %{"payload" => payload}} <-
           Connection.call(client, {:query, query, variables}) do
      {:ok, payload}
    end
  end

  @spec subscribe(client, String.t(), map, pid) ::
          {:ok, subscription_id :: String.t()} | {:error, term}
  def subscribe(client, query, variables \\ %{}, listener \\ self()) do
    with {:ok, %{"id" => id}} <-
           Connection.call(client, {:subscribe, query, variables, listener}) do
      {:ok, id}
    end
  end

  @doc false
  @spec child_spec(term) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  # Callbacks

  @impl true
  def init(%Options{} = opts) do
    {:connect, nil, %State{options: opts}}
  end

  @impl true
  def connect(_info, %State{options: opts} = state) do
    with {:ok, pid} <-
           :gun.open(
             String.to_charlist(opts.host),
             opts.port,
             %{protocols: [:http]}
           ),
         {:ok, _protocol} <- :gun.await_up(pid, opts.connect_timeout),
         stream_ref = :gun.ws_upgrade(pid, opts.path),
         :ok <- wait_for_upgrade(opts.upgrade_timeout),
         :ok <-
           init_connection(
             pid,
             stream_ref,
             opts.init_payload,
             opts.init_timeout
           ) do
      {:ok,
       %{
         state
         | pid: pid,
           monitor_ref: Process.monitor(pid),
           stream_ref: stream_ref
       }}
    else
      reason ->
        Logger.error("Connection failed: #{inspect(reason)}")
        {:backoff, opts.backoff_interval, state}
    end
  end

  defp init_connection(pid, stream_ref, init_payload, timeout) do
    push_message(pid, stream_ref, %{
      type: "connection_init",
      payload: init_payload
    })

    receive do
      {:gun_ws, _pid, _stream_ref, {:text, payload}} ->
        case Config.json_library().decode!(payload) do
          %{"type" => "connection_ack"} -> :ok
          msg -> {:error, {:unexpected_message, msg}}
        end
    after
      timeout ->
        {:error, :timeout}
    end
  end

  defp push_message(pid, stream_ref, msg) do
    :gun.ws_send(
      pid,
      stream_ref,
      {:text, Config.json_library().encode!(msg)}
    )
  end

  @impl true
  def disconnect(info, %State{} = state) do
    close_connection(state)

    state = %{state | pid: nil, monitor_ref: nil, stream_ref: nil}

    case info do
      {:close, from} ->
        Connection.reply(from, :ok)

      reason ->
        Logger.error("Disconnected: #{inspect(reason)}")
    end

    {:connect, :reconnect, state}
  end

  @impl true
  def terminate(_reason, %State{} = state) do
    close_connection(state)
  end

  defp close_connection(%State{monitor_ref: monitor_ref, pid: pid}) do
    if monitor_ref do
      Process.demonitor(monitor_ref)
    end

    if pid do
      :ok = :gun.close(pid)
    end
  end

  @impl true
  def handle_call(:close, from, %State{} = state) do
    {:disconnect, {:close, from}, state}
  end

  def handle_call({:query, query, variables}, from, %State{} = state) do
    id = UUID.uuid4()

    :ok =
      :gun.ws_send(
        state.pid,
        state.stream_ref,
        {:text,
         Config.json_library().encode!(make_message(id, query, variables))}
      )

    {:noreply, State.register_query(state, id, from)}
  end

  def handle_call(
        {:subscribe, query, variables, listener},
        _from,
        %State{} = state
      ) do
    id = UUID.uuid4()

    :ok =
      :gun.ws_send(
        state.pid,
        state.stream_ref,
        {:text,
         Config.json_library().encode!(make_message(id, query, variables))}
      )

    {:reply, {:ok, id}, State.add_listener(state, id, listener)}
  end

  @impl true
  def handle_info(
        {:DOWN, _ref, :process, pid, _reason},
        %State{pid: pid} = state
      ) do
    Logger.warn("Websocket process went down: #{inspect(pid)}")
    {:disconnect, :ws_process_down, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %State{} = state) do
    Logger.info("Listener went down: #{inspect(pid)}")
    {:noreply, State.remove_listener_by_pid(state, pid)}
  end

  def handle_info({:gun_error, _pid, _stream_ref, reason}, %State{} = state) do
    {:stop, reason, state}
  end

  def handle_info(
        {:gun_ws, _pid, _stream_ref, {:text, payload}},
        %State{} = state
      ) do
    message = Config.json_library().decode!(payload)

    state =
      case message do
        %{"id" => id, "type" => "complete"} ->
          state
          |> State.remove_listener(id)
          |> State.unregister_query(id)

        %{"id" => id} ->
          dispatch(id, message, state)

        _ ->
          state
      end

    {:noreply, state}
  end

  def handle_info({:gun_ws, _pid, _stream_ref, {:close, code, payload}}, state) do
    Enum.each(state.queries, fn {_, from} ->
      GenServer.reply(from, {:error, code, payload})
    end)

    {:disconnect, :server_closed, %{state | queries: %{}}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp dispatch(id, message, state) do
    cond do
      Map.has_key?(state.listeners, id) ->
        listener = Map.fetch!(state.listeners, id)
        send(listener, {:subscription, id, message["payload"]})

      Map.has_key?(state.queries, id) ->
        ref = Map.fetch!(state.queries, id)
        GenServer.reply(ref, {:ok, message})
    end

    state
  end

  defp make_message(id, query, variables) do
    %{
      id: id,
      type: "subscribe",
      payload: %{
        query: query,
        variables: Map.new(variables)
      }
    }
  end

  defp wait_for_upgrade(timeout) do
    receive do
      {:gun_upgrade, _pid, _stream_ref, ["websocket"], _headers} ->
        :ok

      {:gun_response, _pid, _stream_ref, _, status, _headers} ->
        {:error, status}

      {:gun_error, _pid, _stream_ref, reason} ->
        {:error, reason}
    after
      timeout ->
        {:error, :timeout}
    end
  end
end
