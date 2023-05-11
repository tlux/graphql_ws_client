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
    Client,
    Config,
    Conn,
    Driver,
    Event,
    Message,
    QueryError,
    SocketError,
    State
  }

  @default_timeout 5000

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
      @behaviour Client

      @doc false
      @spec __config__() :: Config.t()
      def __config__ do
        unquote(otp_app)
        |> Application.get_env(__MODULE__, [])
        |> Config.new()
      end

      @impl Client
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

      @impl Client
      def open(timeout \\ unquote(@default_timeout)) do
        unquote(__MODULE__).open(__MODULE__, timeout)
      end

      @impl Client
      def open!(timeout \\ unquote(@default_timeout)) do
        unquote(__MODULE__).open!(__MODULE__, timeout)
      end

      @impl Client
      def open_with(init_payload, timeout \\ unquote(@default_timeout)) do
        unquote(__MODULE__).open_with(__MODULE__, init_payload, timeout)
      end

      @impl Client
      def open_with!(init_payload, timeout \\ unquote(@default_timeout)) do
        unquote(__MODULE__).open_with!(__MODULE__, init_payload, timeout)
      end

      @impl Client
      def close(timeout \\ unquote(@default_timeout)) do
        unquote(__MODULE__).close(__MODULE__, timeout)
      end

      @impl Client
      def query(query, variables \\ %{}, timeout \\ unquote(@default_timeout)) do
        unquote(__MODULE__).query(__MODULE__, query, variables, timeout)
      end

      @impl Client
      def query!(query, variables \\ %{}, timeout \\ unquote(@default_timeout)) do
        unquote(__MODULE__).query!(__MODULE__, query, variables, timeout)
      end

      @impl Client
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

      @impl Client
      def subscribe!(
            query,
            variables \\ %{},
            listener \\ self(),
            timeout \\ unquote(@default_timeout)
          ) do
        unquote(__MODULE__).subscribe!(
          __MODULE__,
          query,
          variables,
          listener,
          timeout
        )
      end

      @impl Client
      def unsubscribe(subscription_id, timeout \\ unquote(@default_timeout)) do
        unquote(__MODULE__).unsubscribe(__MODULE__, subscription_id, timeout)
      end

      @impl Client
      def unsubscribe!(subscription_id, timeout \\ unquote(@default_timeout)) do
        unquote(__MODULE__).unsubscribe!(__MODULE__, subscription_id, timeout)
      end

      defoverridable child_spec: 1
    end
  end

  @doc """
  Starts a GraphQL-over-Websocket client.

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
  Starts a GraphQL-over-Websocket client using the given config and `GenServer`
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
  Opens the connection to the websocket. Raises on error.
  """
  @spec open!(client, timeout) :: :ok | no_return
  def open!(client, timeout \\ @default_timeout) do
    client
    |> open(timeout)
    |> bang!()
  end

  @doc """
  Opens the connection to the websocket using a custom payload.
  """
  @spec open_with(client, any, timeout) :: :ok | {:error, Exception.t()}
  def open_with(client, init_payload, timeout \\ @default_timeout) do
    Connection.call(client, {:open_with, init_payload}, timeout)
  end

  @doc """
  Opens the connection to the websocket using a custom payload. Raises on error.
  """
  @spec open_with!(client, any, timeout) :: :ok | no_return
  def open_with!(client, init_payload, timeout \\ @default_timeout) do
    client
    |> open_with(init_payload, timeout)
    |> bang!()
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

  ## Example

      iex> GraphQLWSClient.query(
      ...>   client,
      ...>   "query GetPost($id: ID!) { post(id: $id) { body } }",
      ...>   %{"id" => 1337}
      ...> )
      {:ok, %{"data" => %{"posts" => %{"body" => "Lorem Ipsum"}}}}
  """
  @spec query(client, query, variables, timeout) ::
          {:ok, any} | {:error, Exception.t()}
  def query(client, query, variables \\ %{}, timeout \\ @default_timeout) do
    Connection.call(client, {:query, query, variables}, timeout)
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
  @spec query!(client, query, variables, timeout) :: any | no_return
  def query!(client, query, variables \\ %{}, timeout \\ @default_timeout) do
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
  @spec subscribe(client, query, variables, pid, timeout) ::
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
  @spec subscribe!(client, query, variables, pid, timeout) ::
          subscription_id | no_return
  def subscribe!(
        client,
        query,
        variables \\ %{},
        listener \\ self(),
        timeout \\ @default_timeout
      ) do
    client
    |> subscribe(query, variables, listener, timeout)
    |> bang!()
  end

  @doc """
  Removes a subscription.

  ## Example

      iex> GraphQLWSClient.unsubscribe(client, #{inspect(UUID.uuid4())})
      :ok
  """
  @spec unsubscribe(client, subscription_id, timeout) ::
          :ok | {:error, Exception.t()}
  def unsubscribe(client, subscription_id, timeout \\ @default_timeout) do
    Connection.call(client, {:unsubscribe, subscription_id}, timeout)
  end

  @doc """
  Removes a subscription. Raises on error.

  ## Example

      iex> GraphQLWSClient.unsubscribe!(client, #{inspect(UUID.uuid4())})
      :ok
  """
  @spec unsubscribe!(client, subscription_id, timeout) :: :ok | no_return
  def unsubscribe!(client, subscription_id, timeout \\ @default_timeout) do
    client
    |> unsubscribe(subscription_id, timeout)
    |> bang!()
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
    Logger.debug(fn ->
      "[graphql_ws_client] Connecting to #{config.host}:#{config.port} " <>
        "at #{config.path}"
    end)

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
        Logger.debug("[graphql_ws_client] Connected")
        {:ok, State.put_conn(state, conn, monitor_ref)}

      {:error, error} ->
        case info do
          {:open, from, _} ->
            Connection.reply(from, {:error, error})

          _ ->
            Logger.error("[graphql_ws_client] #{Exception.message(error)}")
        end

        {:backoff, config.backoff_interval, state}
    end
  end

  @impl true
  def disconnect({:close, from}, %State{} = state) do
    state = close_connection(state)
    Connection.reply(from, :ok)
    Logger.debug("[graphql_ws_client] Closed")
    {:noconnect, %{state | init_payload: state.config.init_payload}}
  end

  def disconnect(info, %State{} = state) do
    state = close_connection(state)

    Logger.error(fn ->
      "[graphql_ws_client] Disconnected: #{inspect(info)}"
    end)

    {:connect, :reconnect, state}
  end

  @impl true
  def terminate(_reason, %State{} = state) do
    Logger.debug("[graphql_ws_client] Disconnected")
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

  def handle_call({:query, query, variables}, from, %State{} = state) do
    Logger.debug(fn ->
      "[graphql_ws_client] Query - #{inspect(query)} (#{inspect(variables)})"
    end)

    id = UUID.uuid4()
    Driver.push_message(state.conn, build_message(id, query, variables))

    {:noreply, State.add_query(state, id, from)}
  end

  def handle_call(
        {:subscribe, query, variables, listener},
        _from,
        %State{} = state
      ) do
    id = UUID.uuid4()

    Logger.debug(fn ->
      "[graphql_ws_client] Subscribed #{id} with #{inspect(listener)} " <>
        "- #{inspect(query)} (#{inspect(variables)})"
    end)

    Driver.push_message(state.conn, build_message(id, query, variables))

    {:reply, {:ok, id}, State.add_listener(state, id, listener)}
  end

  def handle_call({:unsubscribe, id}, _from, %State{} = state) do
    Driver.push_message(state.conn, %Message{type: :complete, id: id})
    Logger.debug("[graphql_ws_client] Unsubscribed #{id}")
    {:reply, :ok, State.remove_listener(state, id)}
  end

  @impl true
  def handle_info(
        {:DOWN, _ref, :process, pid, _reason},
        %State{conn: %Conn{pid: pid}} = state
      ) do
    handle_socket_down(state)
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %State{} = state) do
    Logger.debug(fn ->
      "[graphql_ws_client] Subscriptions removed as listener process " <>
        "#{inspect(pid)} went down"
    end)

    {:noreply, State.remove_listener_by_pid(state, pid)}
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
        Logger.debug(fn ->
          "[graphql_ws_client] Ignored payload: #{inspect(msg)}"
        end)

        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug(fn ->
      "[graphql_ws_client] Ignored payload: #{inspect(msg)}"
    end)

    {:noreply, state}
  end

  defp handle_socket_down(%State{} = state) do
    Logger.warn(fn ->
      "[graphql_ws_client] Websocket process " <>
        "#{inspect(state.conn.pid)} went down"
    end)

    error = %SocketError{cause: :closed}
    {:disconnect, :socket_down, flush_subscriptions_with_error(error, state)}
  end

  defp handle_message(%Message{type: :complete, id: id}, %State{} = state) do
    Logger.debug("[graphql_ws_client] Message #{id} complete")
    {:noreply, State.remove_subscription(state, id)}
  end

  defp handle_message(
         %Message{type: :error, id: id, payload: payload},
         %State{} = state
       ) do
    error = %QueryError{errors: payload}

    case State.fetch_subscription(state, id) do
      {:ok, {:query, recipient}} ->
        Connection.reply(recipient, {:error, error})

      {:ok, {:listener, listener}} ->
        Logger.debug(fn ->
          "[graphql_ws_client] Message #{id} received (error): " <>
            inspect(error)
        end)

        send(listener, %Event{
          subscription_id: id,
          status: :error,
          result: error
        })

      :error ->
        Logger.debug(fn ->
          "[graphql_ws_client] Message #{id} received (discarded): " <>
            inspect(payload)
        end)
    end

    {:noreply, state}
  end

  defp handle_message(
         %Message{type: :next, id: id, payload: payload},
         %State{} = state
       ) do
    case State.fetch_subscription(state, id) do
      {:ok, {:query, recipient}} ->
        Connection.reply(recipient, {:ok, payload})

      {:ok, {:listener, listener}} ->
        Logger.debug(fn ->
          "[graphql_ws_client] Message #{id} received (OK): #{inspect(payload)}"
        end)

        send(listener, %Event{
          subscription_id: id,
          status: :ok,
          result: payload
        })

      :error ->
        Logger.debug(fn ->
          "[graphql_ws_client] Message #{id} received (discarded): " <>
            inspect(payload)
        end)
    end

    {:noreply, state}
  end

  defp handle_error(error, %State{} = state) do
    Logger.error("[graphql_ws_client] #{Exception.message(error)}")

    {:disconnect, :socket_error, flush_subscriptions_with_error(error, state)}
  end

  defp flush_subscriptions_with_error(error, state) do
    Enum.each(state.queries, fn {_, from} ->
      Connection.reply(from, {:error, error})
    end)

    Enum.each(state.listeners, fn {subscription_id, listener} ->
      send(listener, %Event{
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

  defp build_message(id, query, variables) do
    %Message{
      type: :subscribe,
      id: id,
      payload: %{
        query: query,
        variables: Map.new(variables)
      }
    }
  end

  defp bang!(:ok), do: :ok
  defp bang!({:ok, result}), do: result
  defp bang!({:error, error}), do: raise(error)
end
