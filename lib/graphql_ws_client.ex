defmodule GraphQLWSClient do
  @moduledoc """
  An extensible client for connecting to GraphQL websockets that are implemented
  following
  the [graphql-ws](https://github.com/enisdenjo/graphql-ws) conventions.

  ## Example

      {:ok, socket} = GraphQLWSClient.start_link(url: "ws://localhost:4000/socket")

      {:ok, subscription_id} = GraphQLWSClient.subscribe(
        socket,
        "subscription PostCreated { ... }"
      )

      {:ok, _} = GraphQLWSClient.query(socket, "mutation CreatePost { ... }")

      receive do
        %GraphQLWSClient.Event{} = event ->
          IO.inspect(event)
      end

      GraphQLClient.close(socket)

  ## Custom Client

  If you want to run the client as part of a supervision tree in your
  application, you can also `use GraphQLWSClient` to create your own client.

      defmodule MyClient do
        use GraphQLWSClient, otp_app: :my_app
      end

  Then, you can configure your client using a config file:

      import Config

      config :my_app, MyClient,
        url: "ws://localhost:4000/socket"

  See `GraphQLWSClient.Config.new/1` for a list of available options.
  """

  use Connection

  require Logger

  alias GraphQLWSClient.{
    Config,
    Conn,
    Driver,
    Event,
    Message,
    QueryError,
    SocketError,
    State
  }

  @client_timeout :infinity

  @typedoc """
  Type for a client process.
  """
  @type client :: GenServer.server()

  @typedoc """
  Type for a subscription ID.
  """
  @type subscription_id :: String.t()

  @typedoc """
  Type for a query, mutation or subscription string.
  """
  @type query :: String.t()

  @typedoc """
  Type for variables that are interpolated into the query.
  """
  @type variables :: %{optional(atom | String.t()) => any} | Keyword.t()

  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    quote location: :keep do
      @doc false
      @spec __config__() :: Config.t()
      def __config__ do
        unquote(otp_app)
        |> Application.get_env(__MODULE__, [])
        |> Config.new()
      end

      @doc """
      Starts the `#{unquote(__MODULE__)}`.
      """
      def start_link(opts \\ []) do
        unquote(__MODULE__).start_link(
          __config__(),
          Keyword.put_new(opts, :name, __MODULE__)
        )
      end

      @doc """
      The default child specification.
      """
      @spec child_spec(term) :: Supervisor.child_spec()
      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]}
        }
      end

      defoverridable child_spec: 1
    end
  end

  @doc """
  Starts a GraphQL Websocket client.

  ## Options

  See `GraphQLWSClient.Config.new/1` for a list of available options.
  Additionally, you may pass `t:GenServer.options/0`.
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
  Starts a GraphQL Websocket client using the given config and `GenServer`
  options.

  ## Options

  The first argument accept options as specified in
  `GraphQLWSClient.Config.new/1`. The second argument accepts
  `t:GenServer.options/0`.
  """
  @spec start_link(Config.t() | Keyword.t() | map, GenServer.options()) ::
          GenServer.on_start()
  def start_link(config, opts) do
    Connection.start_link(__MODULE__, Config.new(config), opts)
  end

  @doc """
  Indicates whether the client is connected to the Websocket.
  """
  @spec connected?(client) :: boolean
  def connected?(client) do
    Connection.call(client, :connected?, @client_timeout)
  end

  @doc """
  Opens the connection to the websocket.
  """
  @spec open(client) :: :ok | {:error, Exception.t()}
  def open(client) do
    Connection.call(client, :open, @client_timeout)
  end

  @doc """
  Opens the connection to the websocket. Raises on error.
  """
  @spec open!(client) :: :ok | no_return
  def open!(client) do
    client |> open() |> bang!()
  end

  @doc """
  Opens the connection to the websocket using a custom payload.
  """
  @doc since: "1.0.0"
  @spec open_with(client, any) :: :ok | {:error, Exception.t()}
  def open_with(client, init_payload) do
    Connection.call(client, {:open_with, init_payload}, @client_timeout)
  end

  @doc """
  Opens the connection to the websocket using a custom payload. Raises on error.
  """
  @doc since: "1.0.0"
  @spec open_with!(client, any) :: :ok | no_return
  def open_with!(client, init_payload) do
    client |> open_with(init_payload) |> bang!()
  end

  @doc """
  Closes the connection to the websocket.
  """
  @spec close(client) :: :ok
  def close(client) do
    Connection.call(client, :close, @client_timeout)
  end

  @doc """
  Sends a GraphQL query or mutation to the websocket and returns the result.

  ## Example

      iex> GraphQLWSClient.query(
      ...>   client,
      ...>   "query GetPost($id: ID!) { post(id: $id) { body } }",
      ...>   %{"id" => 1337}
      ...> )
      {:ok, %{"data" => %{"posts" => %{"body" => "Lorem Ipsum"}}}}
  """
  @spec query(client, query, variables, nil | timeout) ::
          {:ok, any} | {:error, Exception.t()}
  def query(client, query, variables \\ %{}, timeout \\ nil) do
    Connection.call(
      client,
      {:query, query, variables, timeout},
      @client_timeout
    )
  end

  @doc """
  Sends a GraphQL query or mutation to the websocket and returns the result.
  Raises on error.

  ## Example

      iex> GraphQLWSClient.query!(
      ...>   client,
      ...>   "query GetPost($id: ID!) { post(id: $id) { body } }",
      ...>   %{"id" => 1337}
      ...> )
      %{"data" => %{"posts" => %{"body" => "Lorem Ipsum"}}}
  """
  @spec query!(client, query, variables, nil | timeout) :: any | no_return
  def query!(client, query, variables \\ %{}, timeout \\ nil) do
    case query(client, query, variables, timeout) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Sends a GraphQL subscription to the websocket and registers a listener process
  to retrieve events.

  ## Example

      iex> GraphQLWSClient.subscribe(
      ...>   client,
      ...>   \"""
      ...>     subscription CommentAdded($postId: ID!) {
      ...>       commentAdded(postId: $postId) { body }
      ...>     }
      ...>   \""",
      ...>   %{"postId" => 1337}
      ...> )
      {:ok, #{inspect(UUID.uuid4())}}
  """
  @spec subscribe(client, query, variables, pid) ::
          {:ok, subscription_id} | {:error, Exception.t()}
  def subscribe(client, query, variables \\ %{}, listener \\ self()) do
    Connection.call(
      client,
      {:subscribe, query, variables, listener},
      @client_timeout
    )
  end

  @doc """
  Sends a GraphQL subscription to the websocket and registers a listener process
  to retrieve events. Raises on error.

  ## Example

      iex> GraphQLWSClient.subscribe!(
      ...>   client,
      ...>   \"""
      ...>     subscription CommentAdded($postId: ID!) {
      ...>       commentAdded(postId: $postId) { body }
      ...>     }
      ...>   \""",
      ...>   %{"postId" => 1337}
      ...> )
      #{inspect(UUID.uuid4())}
  """
  @spec subscribe!(client, query, variables, pid) :: subscription_id | no_return
  def subscribe!(client, query, variables \\ %{}, listener \\ self()) do
    client
    |> subscribe(query, variables, listener)
    |> bang!()
  end

  @doc """
  Removes a subscription.

  ## Example

      iex> GraphQLWSClient.unsubscribe(client, #{inspect(UUID.uuid4())})
      :ok
  """
  @spec unsubscribe(client, subscription_id) :: :ok | {:error, Exception.t()}
  def unsubscribe(client, subscription_id) do
    Connection.call(client, {:unsubscribe, subscription_id}, @client_timeout)
  end

  @doc """
  Removes a subscription. Raises on error.

  ## Example

      iex> GraphQLWSClient.unsubscribe!(client, #{inspect(UUID.uuid4())})
      :ok
  """
  @spec unsubscribe!(client, subscription_id) :: :ok | no_return
  def unsubscribe!(client, subscription_id) do
    client |> unsubscribe(subscription_id) |> bang!()
  end

  @doc """
  The default child specification that can be used to run the client under a
  supervisor.
  """
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

    state = %State{
      config: config,
      init_payload: config.init_payload
    }

    if config.connect_on_start do
      {:connect, :init, state}
    else
      {:ok, state}
    end
  end

  @impl true
  def connect(info, %State{config: config} = state) do
    Logger.debug(
      fmt_log("Connecting to #{config.host}:#{config.port} at #{config.path}")
    )

    init_payload =
      case info do
        {:open, _, {:payload, init_payload}} -> init_payload
        _ -> state.init_payload
      end

    state = %{state | init_payload: init_payload}

    case Driver.connect(config, init_payload) do
      {:ok, %Conn{} = conn} ->
        with {:open, from, _} <- info do
          Connection.reply(from, :ok)
        end

        monitor_ref = Process.monitor(conn.pid)

        Logger.debug(fmt_log("Connected"))

        {:ok, State.put_conn(state, conn, monitor_ref)}

      {:error, error} ->
        case info do
          {:open, from, _} ->
            Connection.reply(from, {:error, error})

          _ ->
            Logger.error(fmt_log(error))
        end

        {:backoff, config.backoff_interval, state}
    end
  end

  @impl true
  def disconnect({:close, from}, %State{} = state) do
    state = close_connection(state)
    Connection.reply(from, :ok)

    Logger.debug(fmt_log("Closed"))

    {:noconnect, %{state | init_payload: state.config.init_payload}}
  end

  def disconnect(info, %State{} = state) do
    state = close_connection(state)

    Logger.error(fmt_log("Disconnected: #{inspect(info)}"))

    {:connect, :reconnect, state}
  end

  @impl true
  def terminate(_reason, %State{} = state) do
    Logger.debug(fmt_log("Terminated"))

    close_connection(state)
  end

  @impl true
  def handle_call(:open, from, %State{} = state) do
    {:connect, {:open, from, nil}, state}
  end

  def handle_call({:open_with, init_payload}, from, %State{} = state) do
    {:connect, {:open, from, {:payload, init_payload}}, state}
  end

  def handle_call(:close, from, %State{} = state) do
    {:disconnect, {:close, from}, state}
  end

  def handle_call(:connected?, _from, %State{connected?: connected?} = state) do
    {:reply, connected?, state}
  end

  def handle_call(_msg, _from, %State{connected?: false} = state) do
    {:reply, {:error, %SocketError{cause: :closed}}, state}
  end

  def handle_call({:query, query, variables, timeout}, from, %State{} = state) do
    id = push_subscription(state.conn, query, variables)

    timeout_ref =
      Process.send_after(
        self(),
        {:query_timeout, id},
        timeout || state.config.query_timeout
      )

    Logger.debug(
      fmt_log("Query #{id} - #{inspect(query)} (#{inspect(variables)})")
    )

    {:noreply,
     State.put_query(state, %State.Query{
       id: id,
       from: from,
       timeout_ref: timeout_ref
     })}
  end

  def handle_call(
        {:subscribe, query, variables, pid},
        _from,
        %State{} = state
      ) do
    id = push_subscription(state.conn, query, variables)
    monitor_ref = Process.monitor(pid)

    Logger.debug(
      fmt_log("Subscribe #{id} - #{inspect(query)} (#{inspect(variables)})")
    )

    {:reply, {:ok, id},
     State.put_listener(state, %State.Listener{
       id: id,
       pid: pid,
       monitor_ref: monitor_ref
     })}
  end

  def handle_call(
        {:unsubscribe, id},
        _from,
        %State{listeners: listeners} = state
      ) do
    Logger.debug(fmt_log("Unsubscribe #{id}"))

    case Map.fetch(listeners, id) do
      {:ok, %State.Listener{monitor_ref: monitor_ref}} ->
        Driver.push_message(state.conn, %Message{type: :complete, id: id})
        Process.demonitor(monitor_ref)

        {:reply, :ok, State.remove_listener(state, id)}

      :error ->
        Logger.debug(fmt_log("Subscription #{id} not found"))
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info(
        {:DOWN, _ref, :process, pid, _reason},
        %State{conn: %Conn{pid: pid}} = state
      ) do
    handle_socket_down(state)
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, %State{} = state) do
    case State.fetch_listener_by_monitor(state, ref) do
      {:ok, %State.Listener{id: id}} ->
        Logger.info(
          fmt_log(
            "Subscription #{id} removed as listener process " <>
              "#{inspect(pid)} went down"
          )
        )

        {:noreply, State.remove_listener(state, id)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:query_timeout, id},
        %State{connected?: true, conn: conn} = state
      ) do
    case Map.fetch(state.queries, id) do
      {:ok, %State.Query{from: from}} ->
        Logger.debug(fmt_log("Query #{id} timed out"))

        Driver.push_message(conn, %Message{id: id, type: :complete})
        Connection.reply(from, {:error, %SocketError{cause: :timeout}})

        {:noreply, State.remove_query(state, id)}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(msg, %State{connected?: true, conn: conn} = state) do
    case Driver.parse_message(conn, msg) do
      {:ok, msg} ->
        handle_message(msg, state)

      {:error, error} ->
        handle_error(error, state)

      :disconnect ->
        handle_socket_down(state)

      :ignore ->
        Logger.debug(fmt_log("Ignored unexpected payload: #{inspect(msg)}"))

        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug(fmt_log("Ignored unexpected payload: #{inspect(msg)}"))

    {:noreply, state}
  end

  defp handle_socket_down(%State{} = state) do
    Logger.warn(fmt_log("Websocket #{inspect(state.conn.pid)} went down"))

    error = %SocketError{cause: :closed}
    {:disconnect, :socket_down, flush_subscriptions_with_error(error, state)}
  end

  defp handle_message(%Message{type: :complete, id: id}, %State{} = state) do
    Logger.debug(fmt_log("Message #{id} - complete"))

    {:noreply, State.remove_subscription(state, id)}
  end

  defp handle_message(
         %Message{type: :error, id: id, payload: payload},
         %State{} = state
       ) do
    error = %QueryError{errors: payload}

    case State.fetch_subscription(state, id) do
      {:ok, %State.Query{from: from, timeout_ref: timeout_ref}} ->
        Process.cancel_timer(timeout_ref)
        Connection.reply(from, {:error, error})

      {:ok, %State.Listener{pid: pid}} ->
        Logger.debug(fmt_log("Message #{id} - error: #{inspect(payload)}"))

        send(pid, %Event{
          subscription_id: id,
          status: :error,
          result: error
        })

      :error ->
        Logger.debug(fmt_log("Message #{id} - discarded: #{inspect(payload)}"))
    end

    {:noreply, state}
  end

  defp handle_message(
         %Message{type: :next, id: id, payload: payload},
         %State{} = state
       ) do
    case State.fetch_subscription(state, id) do
      {:ok, %State.Query{from: from, timeout_ref: timeout_ref}} ->
        Process.cancel_timer(timeout_ref)
        Connection.reply(from, {:ok, payload})

      {:ok, %State.Listener{pid: pid}} ->
        Logger.debug(fmt_log("Message #{id} - OK: #{inspect(payload)}"))

        send(pid, %Event{
          subscription_id: id,
          status: :ok,
          result: payload
        })

      :error ->
        Logger.debug(fmt_log("Message #{id} - discarded: #{inspect(payload)}"))
    end

    {:noreply, state}
  end

  defp handle_error(error, %State{} = state) do
    Logger.error(fmt_log(error))

    {:disconnect, :socket_error, flush_subscriptions_with_error(error, state)}
  end

  defp push_subscription(conn, query, variables) do
    id = UUID.uuid4()

    Driver.push_message(conn, %Message{
      type: :subscribe,
      id: id,
      payload: %{
        query: query,
        variables: Map.new(variables)
      }
    })

    id
  end

  defp flush_subscriptions_with_error(error, state) do
    Enum.each(state.queries, fn {_,
                                 %State.Query{
                                   from: from,
                                   timeout_ref: timeout_ref
                                 }} ->
      Process.cancel_timer(timeout_ref)
      Connection.reply(from, {:error, error})
    end)

    Enum.each(state.listeners, fn {subscription_id, %State.Listener{pid: pid}} ->
      send(pid, %Event{
        subscription_id: subscription_id,
        status: :error,
        result: error
      })
    end)

    State.reset_subscriptions(state)
  end

  defp close_connection(%State{connected?: false} = state), do: state

  defp close_connection(%State{conn: conn, monitor_ref: monitor_ref} = state) do
    Process.demonitor(monitor_ref)
    Driver.disconnect(conn)
    State.reset_conn(state)
  end

  defp bang!(:ok), do: :ok
  defp bang!({:ok, result}), do: result
  defp bang!({:error, error}), do: raise(error)

  defp fmt_log(exception) when is_exception(exception) do
    exception
    |> Exception.message()
    |> fmt_log()
  end

  defp fmt_log(msg), do: "graphql_ws_client: #{msg}"
end
