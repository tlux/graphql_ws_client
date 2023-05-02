defmodule GraphQLWSClient do
  use Connection

  require Logger

  alias GraphQLWSClient.{Config, Event, SocketClosedError, State}

  @type client :: GenServer.server()

  @doc """
  Starts a graphql-ws client.
  """
  @spec start_link(Keyword.t() | GenServer.options()) :: GenServer.on_start()
  def start_link(opts) do
    {config, opts} =
      Keyword.split(
        opts,
        [:url | Map.keys(Config.__struct__())]
      )

    start_link(config, opts)
  end

  @doc """
  Starts a graphql-ws client using the given config and `GenServer` options.
  """
  @spec start_link(Keyword.t() | map, GenServer.options()) ::
          GenServer.on_start()
  def start_link(config, opts) do
    Connection.start_link(__MODULE__, Config.new(config), opts)
  end

  @doc """
  Closes the connection to the websocket.
  """
  @spec close(client) :: :ok
  def close(client) do
    Connection.call(client, :close)
  end

  @doc """
  Sends a GraphQL query or mutation to the websocket and returns the result.
  """
  @spec query(client, String.t(), map) ::
          {:ok, any} | {:error, SocketClosedError.t()}
  def query(client, query, variables \\ %{}) do
    with {:ok, %{"payload" => payload}} <-
           Connection.call(client, {:query, query, variables}) do
      {:ok, payload}
    end
  end

  @doc """
  Sends a GraphQL subscription to the websocket and registers a listener process
  to retrieve events.
  """
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
  def init(%Config{} = config) do
    {:connect, nil, %State{config: config}}
  end

  @impl true
  def connect(_info, %State{config: config} = state) do
    with {:connect, {:ok, pid}} <-
           {:connect,
            :gun.open(
              String.to_charlist(config.host),
              config.port,
              %{protocols: [:http]}
            )},
         {:connected, {:ok, _protocol}} <-
           {:connected, :gun.await_up(pid, config.connect_timeout)},
         {:upgrade, stream_ref} <-
           {:upgrade, :gun.ws_upgrade(pid, config.path)},
         {:upgraded, :ok} <- {:upgraded, await_upgrade(config.upgrade_timeout)},
         {:init, :ok} <- {:init, init_connection(pid, stream_ref, config)} do
      {:ok,
       %{
         state
         | pid: pid,
           monitor_ref: Process.monitor(pid),
           stream_ref: stream_ref
       }}
    else
      {_, reason} ->
        Logger.error("Connection failed: #{inspect(reason)}")
        {:backoff, config.backoff_interval, state}
    end
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

  @impl true
  def handle_call(:close, from, %State{} = state) do
    {:disconnect, {:close, from}, state}
  end

  def handle_call({:query, query, variables}, from, %State{} = state) do
    id = UUID.uuid4()

    push_message(
      state.pid,
      state.stream_ref,
      build_query(id, query, variables)
    )

    {:noreply, State.add_query(state, id, from)}
  end

  def handle_call(
        {:subscribe, query, variables, listener},
        _from,
        %State{} = state
      ) do
    id = UUID.uuid4()

    push_message(
      state.pid,
      state.stream_ref,
      build_query(id, query, variables)
    )

    # TODO: return error when subscription failed!

    {:reply, {:ok, id}, State.add_listener(state, id, listener)}
  end

  @impl true
  def handle_info(
        {:DOWN, _ref, :process, pid, _reason},
        %State{pid: pid} = state
      ) do
    Logger.warn("Websocket process went down: #{inspect(pid)}")
    {:disconnect, :socket_process_down, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %State{} = state) do
    Logger.info("Listener process went down: #{inspect(pid)}")
    {:noreply, State.remove_listener_by_pid(state, pid)}
  end

  def handle_info({:gun_error, _pid, _stream_ref, reason}, %State{} = state) do
    {:disconnect, {:socket_error, reason}, state}
  end

  def handle_info(
        {:gun_ws, _pid, _stream_ref, {:text, payload}},
        %State{} = state
      ) do
    msg = decode_message(state.config.json_library, payload)

    state =
      case msg do
        %{"id" => id, "type" => "complete"} ->
          State.remove_subscription(state, id)

        %{"id" => id} ->
          dispatch(state, id, msg)
          state

        _ ->
          state
      end

    {:noreply, state}
  end

  def handle_info(
        {:gun_ws, _pid, _stream_ref, msg},
        %State{} = state
      ) do
    error =
      case msg do
        {:close, code, payload} ->
          %SocketClosedError{code: code, payload: payload}

        {:close, payload} ->
          %SocketClosedError{payload: payload}
      end

    Enum.each(state.queries, fn {_, from} ->
      Connection.reply(from, {:error, error})
    end)

    {:disconnect, :socket_closed, %{state | queries: %{}}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp dispatch(%State{} = state, id, msg) do
    case State.fetch_subscription(state, id) do
      {:ok, {:listener, listener}} ->
        send(listener, Event.new(id, msg["payload"]))

      {:ok, {:query, recipient}} ->
        Connection.reply(recipient, {:ok, msg})
    end
  end

  defp await_upgrade(timeout) do
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

  defp init_connection(pid, stream_ref, config) do
    push_message(pid, stream_ref, %{
      type: "connection_init",
      payload: config.init_payload
    })

    receive do
      {:gun_error, _pid, _stream_ref, reason} ->
        {:error, {:socket_error, reason}}

      {:gun_ws, _pid, _stream_ref, {:text, payload}} ->
        case decode_message(config.json_library, payload) do
          %{"type" => "connection_ack"} -> :ok
          _ -> {:error, :unexpected_message}
        end

      {:gun_ws, _pid, _stream_ref, _msg} ->
        {:error, :unexpected_message}
    after
      config.init_timeout ->
        {:error, :timeout}
    end
  end

  defp close_connection(%State{monitor_ref: monitor_ref, pid: pid}) do
    if monitor_ref do
      Process.demonitor(monitor_ref)
    end

    if pid do
      :ok = :gun.close(pid)
    end
  end

  defp decode_message(json_library, payload) do
    json_library.decode!(payload)
  end

  defp push_message(pid, stream_ref, json_library, msg) do
    :gun.ws_send(
      pid,
      stream_ref,
      {:text, json_library.encode!(msg)}
    )
  end

  defp build_query(id, query, variables) do
    %{
      id: id,
      type: "subscribe",
      payload: %{
        query: query,
        variables: Map.new(variables)
      }
    }
  end
end
