defmodule GraphQLWSClient do
  @moduledoc """
  An extensible client for connecting to GraphQL websockets that are implemented
  following
  the [graphql-ws](https://github.com/enisdenjo/graphql-ws) conventions.

  ## Example

  Send a query or mutation and return the result immediately:

      {:ok, result} = GraphQLWSClient.query(socket, "query GetPost { ... }")

  Register a subscription to listen for events:

      {:ok, subscription_id} = GraphQLWSClient.subscribe(
        socket,
        "subscription PostCreated { ... }"
      )

      GraphQLWSClient.query!(socket, "mutation CreatePost { ... }")

      receive do
        %GraphQLWSClient.Event{type: :error, id: ^subscription_id, payload: error} ->
          IO.inspect(error, label: "error")
        %GraphQLWSClient.Event{type: :next, id: ^subscription_id, payload: result} ->
          IO.inspect(result)
        %GraphQLWSClient.Event{type: :complete, id: ^subscription_id} ->
          IO.puts("Stream closed")
      end

      GraphQLClient.close(socket)

  You would usually put this inside of a custom `GenServer` and handle the events
  in `handle_info/3`.

  Alternatively, you can create a stream of results:

      socket
      |> GraphQLWSClient.stream!("subscription PostCreated { ... }")
      |> Stream.each(fn result ->
        IO.inspect(result)
      end)
      |> Stream.run()

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

  import GraphQLWSClient.FormatLog

  alias GraphQLWSClient.{
    Config,
    Conn,
    Driver,
    Event,
    GraphQLError,
    Iterator,
    Message,
    OperationError,
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
      @doc """
      Starts the `#{unquote(__MODULE__)}`.
      """
      def start_link(opts \\ []) do
        config =
          unquote(otp_app)
          |> Application.get_env(__MODULE__, [])
          |> Config.new()

        unquote(__MODULE__).start_link(
          config,
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
  Sends a GraphQL subscription to the websocket and returns an event stream.

  ## Options

  * `:buffer_size` - Sets the buffer size. If the buffer is exceeded, the oldest
    events are discarded first. Although it is not recommended, you may also set
    the value to `:infinity` to set no limit. Defaults to `1000`.

  ## Example

      iex> stream = GraphQLWSClient.stream!(
      ...>   client,
      ...>   \"""
      ...>     subscription CommentAdded($postId: ID!) {
      ...>       commentAdded(postId: $postId) { body }
      ...>     }
      ...>   \""",
      ...>   %{"postId" => 1337}
      ...> )

  Print events as they come in:

      iex> stream
      ...> |> Stream.each(fn result -> IO.inspect(result) end)
      ...> |> Stream.run()

  Wait for a fixed number of events to come in and then turn them into a list:

      iex> stream |> Stream.take(3) |> Enum.to_list()
  """
  @doc since: "2.0.0"
  @spec stream!(client, query, variables, Keyword.t()) :: Enumerable.t()
  def stream!(client, query, variables \\ %{}, opts \\ []) do
    Stream.resource(
      fn -> Iterator.open!(client, query, variables, opts) end,
      fn iterator -> {Iterator.next(iterator), iterator} end,
      &Iterator.close/1
    )
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
    Logger.info(
      format_log(
        "Connecting to #{config.host}:#{config.port} at #{config.path}"
      )
    )

    state = put_init_payload(state, info)

    case Driver.connect(config, state.init_payload) do
      {:ok, %Conn{} = conn} ->
        monitor_ref = Process.monitor(conn.pid)

        with {:open, from, _} <- info do
          Connection.reply(from, :ok)
        end

        Logger.info(format_log("Connected"))

        resubscribe_listeners(conn, state.listeners)

        {:ok, State.put_conn(state, conn, monitor_ref)}

      {:error, error} ->
        case info do
          {:open, from, _} ->
            Connection.reply(from, {:error, error})

          _ ->
            Logger.error(format_log(error))
        end

        {:backoff, config.backoff_interval, state}
    end
  end

  defp put_init_payload(%State{} = state, {:open, _, {:payload, init_payload}}) do
    %{state | init_payload: init_payload}
  end

  defp put_init_payload(%State{} = state, _), do: state

  @impl true
  def disconnect({:close, from}, %State{} = state) do
    state = close_connection(state)
    Connection.reply(from, :ok)

    Logger.info(format_log("Closed"))

    {:noconnect, %{state | init_payload: state.config.init_payload}}
  end

  def disconnect({:error, error}, %State{} = state) do
    state = close_connection(state)

    Logger.info(format_log("Disconnected, reconnecting..."))

    flush_queries_with_error(state.queries, error)

    {:connect, :reconnect, State.reset_queries(state)}
  end

  @impl true
  def terminate(reason, %State{} = state) do
    Logger.debug(
      format_log("Terminating client, closing connection: #{inspect(reason)}")
    )

    close_connection(state)
  end

  @impl true
  def handle_call(:open, _from, %State{connected?: true} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:open, from, %State{} = state) do
    {:connect, {:open, from, nil}, state}
  end

  def handle_call({:open_with, _}, _from, %State{connected?: true} = state) do
    {:reply, {:error, %OperationError{message: "Already connected"}}, state}
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

  def handle_call(_info, _from, %State{connected?: false} = state) do
    {:reply, {:error, %SocketError{cause: :closed}}, state}
  end

  def handle_call({:query, query, variables, timeout}, from, %State{} = state) do
    id = UUID.uuid4()
    payload = query_payload(query, variables)
    Driver.push_subscribe(state.conn, id, payload)

    timeout_ref =
      Process.send_after(
        self(),
        {:query_timeout, id},
        timeout || state.config.query_timeout
      )

    Logger.debug(format_log("Query #{id} - #{inspect(payload)})"))

    {:noreply,
     State.put_query(state, %State.Query{
       from: from,
       id: id,
       timeout_ref: timeout_ref
     })}
  end

  def handle_call(
        {:subscribe, query, variables, pid},
        _from,
        %State{} = state
      ) do
    monitor_ref = Process.monitor(pid)
    id = UUID.uuid4()
    payload = query_payload(query, variables)
    Driver.push_subscribe(state.conn, id, payload)

    Logger.debug(format_log("Subscribe #{id} - #{inspect(payload)}"))

    {:reply, {:ok, id},
     State.put_listener(state, %State.Listener{
       id: id,
       monitor_ref: monitor_ref,
       payload: payload,
       pid: pid
     })}
  end

  def handle_call(
        {:unsubscribe, id},
        _from,
        %State{listeners: listeners} = state
      ) do
    Logger.debug(format_log("Unsubscribe #{id}"))

    case Map.fetch(listeners, id) do
      {:ok, %State.Listener{monitor_ref: monitor_ref}} ->
        Driver.push_complete(state.conn, id)
        Process.demonitor(monitor_ref)

        {:reply, :ok, State.remove_listener(state, id)}

      :error ->
        Logger.debug(format_log("Subscription #{id} not found"))

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info(
        {:DOWN, _ref, :process, pid, _reason},
        %State{conn: %Conn{pid: pid}} = state
      ) do
    Logger.error("Socket process crashed")

    {:disconnect, {:error, %SocketError{cause: :closed}}, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %State{} = state) do
    case State.fetch_listener_by_monitor(state, ref) do
      {:ok, %State.Listener{id: id, pid: pid}} ->
        Logger.info(
          format_log(
            "Subscription #{id} removed as listener process " <>
              "#{inspect(pid)} went down with reason #{inspect(reason)}"
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
        Logger.debug(format_log("Query #{id} timed out"))

        Driver.push_complete(conn, id)
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
        Logger.debug(format_log("Socket went down"))

        {:disconnect, {:error, %SocketError{cause: :closed}}, state}

      :ignore ->
        Logger.debug(format_log("Ignored unexpected payload: #{inspect(msg)}"))

        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug(format_log("Ignored unexpected payload: #{inspect(msg)}"))

    {:noreply, state}
  end

  # Helpers

  defp handle_message(%Message{type: :complete, id: id}, %State{} = state) do
    Logger.debug(format_log("Message #{id} - complete"))

    with {:ok, %State.Listener{pid: pid, monitor_ref: monitor_ref}} <-
           Map.fetch(state.listeners, id) do
      Process.demonitor(monitor_ref)
      send(pid, %Event{subscription_id: id, type: :complete})
    end

    {:noreply, State.remove_subscription(state, id)}
  end

  defp handle_message(
         %Message{type: :error, id: id, payload: payload},
         %State{} = state
       ) do
    error = %GraphQLError{errors: payload}

    case State.fetch_subscription(state, id) do
      {:ok, %State.Query{} = query} ->
        reply_to_query(query, {:error, error})
        {:noreply, State.remove_query(state, id)}

      {:ok, %State.Listener{pid: pid, monitor_ref: monitor_ref}} ->
        Logger.debug(format_log("Message #{id} - error: #{inspect(payload)}"))

        Process.demonitor(monitor_ref)
        send(pid, %Event{subscription_id: id, type: :error, payload: error})

        {:noreply, State.remove_listener(state, id)}

      :error ->
        Logger.debug(
          format_log("Message #{id} - discarded: #{inspect(payload)}")
        )

        {:noreply, state}
    end
  end

  defp handle_message(
         %Message{type: :next, id: id, payload: payload},
         %State{} = state
       ) do
    case State.fetch_subscription(state, id) do
      {:ok, %State.Query{} = query} ->
        reply_to_query(query, {:ok, payload})

      {:ok, %State.Listener{pid: pid}} ->
        Logger.debug(format_log("Message #{id} - OK: #{inspect(payload)}"))

        send(pid, %Event{subscription_id: id, type: :next, payload: payload})

      :error ->
        Logger.debug(
          format_log("Message #{id} - discarded: #{inspect(payload)}")
        )
    end

    {:noreply, state}
  end

  defp handle_error(error, %State{} = state) do
    Logger.error(format_log(error))

    {:disconnect, {:error, error}, state}
  end

  defp resubscribe_listeners(conn, listeners) do
    Enum.each(listeners, fn {id, %State.Listener{payload: payload}} ->
      Logger.debug(format_log("Resubscribe #{id} - #{inspect(payload)}"))

      Driver.push_resubscribe(conn, id, payload)
    end)
  end

  defp flush_queries_with_error(queries, error) do
    Enum.each(queries, fn {_, query} ->
      reply_to_query(query, {:error, error})
    end)
  end

  defp reply_to_query(%State.Query{from: from, timeout_ref: timeout_ref}, reply) do
    Process.cancel_timer(timeout_ref)
    Connection.reply(from, reply)
  end

  defp close_connection(%State{connected?: false} = state), do: state

  defp close_connection(%State{conn: conn, monitor_ref: monitor_ref} = state) do
    Process.demonitor(monitor_ref)
    Driver.disconnect(conn)
    State.reset_conn(state)
  end

  defp query_payload(query, variables) do
    %{query: query, variables: Map.new(variables)}
  end

  defp bang!(:ok), do: :ok
  defp bang!({:ok, result}), do: result
  defp bang!({:error, error}), do: raise(error)
end
