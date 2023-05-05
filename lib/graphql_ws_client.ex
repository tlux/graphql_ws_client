defmodule GraphQLWSClient do
  use Connection

  require Logger

  alias GraphQLWSClient.{Config, Event, QueryError, SocketError, State}

  @default_timeout 5000

  @type client :: GenServer.server()
  @type subscription_id :: String.t()
  @type query :: String.t()

  @callback start_link() :: GenServer.on_start()
  @callback start_link(GenServer.options()) :: GenServer.on_start()
  @callback open() :: :ok | {:error, Exception.t()}
  @callback close() :: :ok
  @callback query(query) :: {:ok, any} | {:error, Exception.t()}
  @callback query(query, map) :: {:ok, any} | {:error, Exception.t()}
  @callback query!(query) :: any | no_return
  @callback query!(query, map) :: any | no_return
  @callback subscribe(query) ::
              {:ok, subscription_id} | {:error, Exception.t()}
  @callback subscribe(query, map) ::
              {:ok, subscription_id} | {:error, Exception.t()}
  @callback subscribe(query, map, pid) ::
              {:ok, subscription_id} | {:error, Exception.t()}
  @callback unsubscribe(subscription_id) :: :ok

  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    quote location: :keep do
      @behaviour unquote(__MODULE__)

      @doc false
      @spec __config__() :: Config.t()
      def __config__ do
        unquote(otp_app)
        |> Application.get_env(__MODULE__, [])
        |> Config.new()
      end

      @impl unquote(__MODULE__)
      def start_link(opts \\ []) do
        unquote(__MODULE__).start_link(
          __config__(),
          Keyword.put_new(opts, :name, __MODULE__)
        )
      end

      @doc false
      @spec child_spec(term) :: Supervisor.child_spec()
      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]}
        }
      end

      @impl unquote(__MODULE__)
      def open(timeout \\ unquote(@default_timeout)) do
        unquote(__MODULE__).open(__MODULE__, timeout)
      end

      @impl unquote(__MODULE__)
      def close(timeout \\ unquote(@default_timeout)) do
        unquote(__MODULE__).close(__MODULE__, timeout)
      end

      @impl unquote(__MODULE__)
      def query(query, variables \\ %{}, timeout \\ unquote(@default_timeout)) do
        unquote(__MODULE__).query(__MODULE__, query, variables, timeout)
      end

      @impl unquote(__MODULE__)
      def query!(query, variables \\ %{}, timeout \\ unquote(@default_timeout)) do
        unquote(__MODULE__).query!(__MODULE__, query, variables, timeout)
      end

      @impl unquote(__MODULE__)
      def subscribe(
            query,
            variables \\ %{},
            listener \\ self(),
            timeout \\ unquote(@default_timeout)
          ) do
        unquote(__MODULE__).subscribe(
          __MODULE__,
          query,
          variables,
          listener,
          timeout
        )
      end

      @impl unquote(__MODULE__)
      def unsubscribe(subscription_id, timeout \\ unquote(@default_timeout)) do
        unquote(__MODULE__).unsubscribe(__MODULE__, subscription_id, timeout)
      end
    end
  end

  @doc """
  Starts a graphql-ws client.
  """
  @spec start_link(Config.t() | Keyword.t() | map | GenServer.options()) ::
          GenServer.on_start()
  def start_link(%Config{} = config) do
    start_link(config, [])
  end

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
  @spec start_link(Config.t() | Keyword.t() | map, GenServer.options()) ::
          GenServer.on_start()
  def start_link(config, opts) do
    Connection.start_link(__MODULE__, Config.new(config), opts)
  end

  @doc """
  Indicates whether the client is connected to the Websocket.
  """
  @spec connected?(client, timeout) :: boolean
  def connected?(client, timeout \\ @default_timeout) do
    Connection.call(client, :connected?, timeout)
  end

  @doc """
  Opens the connection to the websocket.
  """
  @spec open(client, timeout) :: :ok | {:error, Exception.t()}
  def open(client, timeout \\ @default_timeout) do
    Connection.call(client, :open, timeout)
  end

  @doc """
  Closes the connection to the websocket.
  """
  @spec close(client, timeout) :: :ok
  def close(client, timeout \\ @default_timeout) do
    Connection.call(client, :close, timeout)
  end

  @doc """
  Sends a GraphQL query or mutation to the websocket and returns the result.
  """
  @spec query(client, query, map, timeout) ::
          {:ok, any} | {:error, Exception.t()}
  def query(client, query, variables \\ %{}, timeout \\ @default_timeout) do
    Connection.call(client, {:query, query, variables}, timeout)
  end

  @doc """
  Sends a GraphQL query or mutation to the websocket and returns the result.
  Raises on error.
  """
  @spec query!(client, query, map, timeout) :: any | no_return
  def query!(client, query, variables \\ %{}, timeout \\ @default_timeout) do
    case query(client, query, variables, timeout) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Sends a GraphQL subscription to the websocket and registers a listener process
  to retrieve events.
  """
  @spec subscribe(client, query, map, pid, timeout) ::
          {:ok, subscription_id} | {:error, Exception.t()}
  def subscribe(
        client,
        query,
        variables \\ %{},
        listener \\ self(),
        timeout \\ @default_timeout
      ) do
    Connection.call(client, {:subscribe, query, variables, listener}, timeout)
  end

  @doc """
  Removes a subscription.
  """
  @spec unsubscribe(client, subscription_id, timeout) :: :ok
  def unsubscribe(client, subscription_id, timeout \\ @default_timeout) do
    Connection.call(client, {:unsubscribe, subscription_id}, timeout)
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
    Process.flag(:trap_exit, true)
    state = %State{config: config}

    if config.connect_on_start do
      {:connect, :init, state}
    else
      {:ok, state}
    end
  end

  @impl true
  def connect(info, %State{config: config} = state) do
    with {:ok, pid} <-
           config.ws_client.open(
             String.to_charlist(config.host),
             config.port,
             %{protocols: [:http]}
           ),
         {:ok, _protocol} <-
           config.ws_client.await_up(pid, config.connect_timeout),
         stream_ref = config.ws_client.ws_upgrade(pid, config.path),
         :ok <- await_upgrade(config.upgrade_timeout),
         :ok <- init_connection(pid, stream_ref, config),
         :ok <- await_connection_ack(config) do
      with {:open, from} <- info do
        Connection.reply(from, :ok)
      end

      {:ok,
       %{
         state
         | connected?: true,
           pid: pid,
           monitor_ref: Process.monitor(pid),
           stream_ref: stream_ref
       }}
    else
      error ->
        case info do
          {:open, from} ->
            Connection.reply(from, error)

          reason ->
            Logger.error("Connection failed: #{inspect(reason)}")
        end

        {:backoff, config.backoff_interval, state}
    end
  end

  @impl true
  def disconnect({:close, from}, %State{} = state) do
    state = close_connection(state)
    Connection.reply(from, :ok)
    {:noconnect, state}
  end

  def disconnect(info, %State{} = state) do
    state = close_connection(state)
    Logger.error("Disconnected: #{inspect(info)}")
    {:connect, :reconnect, state}
  end

  @impl true
  def terminate(_reason, %State{} = state) do
    close_connection(state)
  end

  @impl true
  def handle_call(:open, from, %State{} = state) do
    {:connect, {:open, from}, state}
  end

  def handle_call(:close, from, %State{} = state) do
    {:disconnect, {:close, from}, state}
  end

  def handle_call(:connected?, _from, %State{connected?: connected?} = state) do
    {:reply, connected?, state}
  end

  def handle_call({:query, _, _}, _from, %State{connected?: false} = state) do
    {:reply, {:error, %SocketError{cause: :closed}}, state}
  end

  def handle_call({:query, query, variables}, from, %State{} = state) do
    id = UUID.uuid4()
    push_message(state, build_query(id, query, variables))

    {:noreply, State.add_query(state, id, from)}
  end

  def handle_call(
        {:subscribe, _, _, _},
        _from,
        %State{connected?: false} = state
      ) do
    {:reply, {:error, %SocketError{cause: :closed}}, state}
  end

  def handle_call(
        {:subscribe, query, variables, listener},
        _from,
        %State{} = state
      ) do
    id = UUID.uuid4()
    push_message(state, build_query(id, query, variables))

    {:reply, {:ok, id}, State.add_listener(state, id, listener)}
  end

  def handle_call(
        {:unsubscribe, subscription_id},
        _from,
        %State{} = state
      ) do
    push_message(state, %{id: subscription_id, type: "complete"})

    {:reply, :ok, State.remove_listener(state, subscription_id)}
  end

  @impl true
  def handle_info(
        {:DOWN, _ref, :process, pid, _reason},
        %State{pid: pid} = state
      ) do
    Logger.warn("Websocket process went down: #{inspect(pid)}")

    Enum.each(state.queries, fn {_, from} ->
      Connection.reply(from, {:error, %SocketError{cause: :closed}})
    end)

    {:disconnect, :socket_down, State.reset_queries(state)}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %State{} = state) do
    Logger.info("Listener process went down: #{inspect(pid)}")
    {:noreply, State.remove_listener_by_pid(state, pid)}
  end

  def handle_info({:gun_error, _pid, _stream_ref, reason}, %State{} = state) do
    Enum.each(state.queries, fn {_, from} ->
      Connection.reply(
        from,
        {:error, %SocketError{cause: :result, details: %{reason: reason}}}
      )
    end)

    {:disconnect, :socket_error, State.reset_queries(state)}
  end

  def handle_info(
        {:gun_ws, _pid, _stream_ref, {:text, text}},
        %State{} = state
      ) do
    state =
      case decode_message(state.config.json_library, text) do
        %{"type" => "complete", "id" => id} ->
          State.remove_subscription(state, id)

        %{"type" => type, "id" => id, "payload" => payload} ->
          dispatch(state, type, id, payload)
          state

        _ ->
          state
      end

    {:noreply, state}
  end

  def handle_info({:gun_ws, _pid, _stream_ref, :close}, %State{} = state) do
    handle_close_frame(state, %SocketError{cause: :closed})
  end

  def handle_info(
        {:gun_ws, _pid, _stream_ref, {:close, payload}},
        %State{} = state
      ) do
    handle_close_frame(state, %SocketError{
      cause: :closed,
      details: %{payload: payload}
    })
  end

  def handle_info(
        {:gun_ws, _pid, _stream_ref, {:close, code, payload}},
        %State{} = state
      ) do
    handle_close_frame(state, %SocketError{
      cause: :closed,
      details: %{code: code, payload: payload}
    })
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp handle_close_frame(%State{} = state, error) do
    Enum.each(state.queries, fn {_, from} ->
      Connection.reply(from, {:error, error})
    end)

    {:disconnect, :socket_closed, State.reset_queries(state)}
  end

  defp dispatch(%State{} = state, "error", id, payload) do
    error = %QueryError{errors: payload}

    case State.fetch_subscription(state, id) do
      {:ok, {:query, recipient}} ->
        Connection.reply(recipient, {:error, error})

      {:ok, {:listener, listener}} ->
        send(listener, %Event{subscription_id: id, error: error})

      :error ->
        Logger.info("Unexpected payload: #{payload}")
        :noop
    end
  end

  defp dispatch(%State{} = state, "next", id, payload) do
    case State.fetch_subscription(state, id) do
      {:ok, {:query, recipient}} ->
        Connection.reply(recipient, {:ok, payload})

      {:ok, {:listener, listener}} ->
        send(listener, %Event{subscription_id: id, result: payload})

      :error ->
        Logger.info("Unexpected payload: #{payload}")
        :noop
    end
  end

  defp await_upgrade(timeout) do
    receive do
      {:gun_upgrade, _pid, _stream_ref, ["websocket"], _headers} ->
        :ok

      {:gun_response, _pid, _stream_ref, _is_fin, status, _headers} ->
        {:error, %SocketError{cause: :result, details: %{status: status}}}

      {:gun_error, _pid, _stream_ref, reason} ->
        {:error, %SocketError{cause: :result, details: %{reason: reason}}}
    after
      timeout ->
        {:error, %SocketError{cause: :timeout}}
    end
  end

  defp init_connection(pid, stream_ref, %Config{} = config) do
    push_message(config.ws_client, pid, stream_ref, config.json_library, %{
      type: "connection_init",
      payload: config.init_payload
    })
  end

  defp await_connection_ack(config) do
    receive do
      {:gun_error, _pid, _stream_ref, reason} ->
        {:error, %SocketError{cause: :result, details: %{reason: reason}}}

      {:gun_ws, _pid, _stream_ref, {:text, msg}} ->
        case decode_message(config.json_library, msg) do
          %{"type" => "connection_ack"} -> :ok
          _ -> {:error, %SocketError{cause: :result}}
        end

      {:gun_ws, _pid, _stream_ref, _msg} ->
        {:error, %SocketError{cause: :result}}
    after
      config.init_timeout ->
        {:error, %SocketError{cause: :timeout}}
    end
  end

  defp close_connection(%State{connected?: false} = state), do: state

  defp close_connection(
         %State{
           config: config,
           monitor_ref: monitor_ref,
           pid: pid
         } = state
       ) do
    Process.demonitor(monitor_ref)
    :ok = config.ws_client.close(pid)

    %{state | connected?: false, pid: nil, monitor_ref: nil, stream_ref: nil}
  end

  defp decode_message(json_library, msg) do
    json_library.decode!(msg)
  end

  defp push_message(state, msg) do
    push_message(
      state.config.ws_client,
      state.pid,
      state.stream_ref,
      state.config.json_library,
      msg
    )
  end

  defp push_message(ws_client, pid, stream_ref, json_library, msg) do
    ws_client.ws_send(pid, stream_ref, {:text, json_library.encode!(msg)})
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
