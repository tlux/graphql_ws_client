defmodule GraphQLWSClientTest do
  use ExUnit.Case

  import ExUnit.CaptureLog
  import Mox

  alias GraphQLWSClient.{Config, Conn, Event, Message, QueryError, SocketError}
  alias GraphQLWSClient.Drivers.MockWithoutInit, as: MockDriver

  @opts [
    backoff_interval: 1000,
    driver: {MockDriver, upgrade_timeout: 1500},
    host: "example.com",
    init_payload: %{"token" => "__token__"},
    path: "/subscriptions",
    port: 1234
  ]

  @config struct!(Config, @opts)

  @conn %Conn{
    config: @config,
    driver: MockDriver,
    opts: %{upgrade_timeout: 1500},
    init_payload: %{"token" => "__token__"}
  }

  @query "query Foo { foo { bar } }"
  @subscription_id "__subscription_id__"
  @variables %{"foo" => "bar"}

  setup :set_mox_from_context
  setup :verify_on_exit!

  describe "start_link/1" do
    test "with config" do
      expect(MockDriver, :connect, fn @conn ->
        {:ok, @conn}
      end)

      assert {:ok, client} = start_supervised({GraphQLWSClient, @config})
      assert GraphQLWSClient.connected?(client) == true
    end

    test "with options" do
      expect(MockDriver, :connect, fn @conn ->
        {:ok, @conn}
      end)

      assert {:ok, client} = start_supervised({GraphQLWSClient, @opts})
      assert GraphQLWSClient.connected?(client) == true
    end

    test "error" do
      error = %SocketError{cause: :timeout}

      expect(MockDriver, :connect, fn @conn ->
        {:error, error}
      end)

      assert capture_log(fn ->
               start_supervised!({GraphQLWSClient, @config})

               # wait a little bit until connection fails
               Process.sleep(100)
             end) =~ Exception.message(error)
    end
  end

  describe "open/1" do
    setup do
      config = %{@config | connect_on_start: false}
      {:ok, config: config, conn: %{@conn | config: config}}
    end

    test "success", %{config: config, conn: conn} do
      expect(MockDriver, :connect, fn ^conn ->
        {:ok, conn}
      end)

      client = start_supervised!({GraphQLWSClient, config})

      assert GraphQLWSClient.connected?(client) == false
      assert GraphQLWSClient.open(client) == :ok
      assert GraphQLWSClient.connected?(client) == true
    end

    test "error", %{config: config, conn: conn} do
      error = %SocketError{cause: :timeout}

      expect(MockDriver, :connect, fn ^conn ->
        {:error, error}
      end)

      client = start_supervised!({GraphQLWSClient, config})

      assert GraphQLWSClient.open(client) == {:error, error}
    end
  end

  describe "open!/1" do
    setup do
      config = %{@config | connect_on_start: false}
      {:ok, config: config, conn: %{@conn | config: config}}
    end

    test "success", %{config: config, conn: conn} do
      expect(MockDriver, :connect, fn ^conn ->
        {:ok, conn}
      end)

      client = start_supervised!({GraphQLWSClient, config})

      assert GraphQLWSClient.connected?(client) == false
      assert GraphQLWSClient.open!(client) == :ok
      assert GraphQLWSClient.connected?(client) == true
    end

    test "error", %{config: config, conn: conn} do
      error = %SocketError{cause: :timeout}

      expect(MockDriver, :connect, fn ^conn ->
        {:error, error}
      end)

      client = start_supervised!({GraphQLWSClient, config})

      assert_raise SocketError, Exception.message(error), fn ->
        GraphQLWSClient.open!(client)
      end
    end
  end

  describe "open_with/1" do
    @init_payload %{"foo" => "bar"}

    setup do
      config = %{@config | connect_on_start: false}
      conn = %{@conn | config: config, init_payload: @init_payload}
      {:ok, config: config, conn: conn}
    end

    test "success", %{config: config, conn: conn} do
      expect(MockDriver, :connect, fn ^conn ->
        {:ok, conn}
      end)

      client = start_supervised!({GraphQLWSClient, config})

      assert GraphQLWSClient.connected?(client) == false
      assert GraphQLWSClient.open_with(client, @init_payload) == :ok
      assert GraphQLWSClient.connected?(client) == true
    end

    test "error", %{config: config, conn: conn} do
      error = %SocketError{cause: :timeout}

      expect(MockDriver, :connect, fn ^conn ->
        {:error, error}
      end)

      client = start_supervised!({GraphQLWSClient, config})

      assert GraphQLWSClient.open_with(client, @init_payload) == {:error, error}
    end

    test "reconnect with original payload when connection closed", %{
      config: config,
      conn: conn
    } do
      reconnect_conn = %{@conn | config: config}

      MockDriver
      |> expect(:connect, fn ^conn -> {:ok, conn} end)
      |> expect(:disconnect, fn ^conn -> :ok end)
      |> expect(:connect, fn ^reconnect_conn -> {:ok, reconnect_conn} end)

      client = start_supervised!({GraphQLWSClient, config})

      assert GraphQLWSClient.open_with(client, @init_payload) == :ok
      assert GraphQLWSClient.close(client) == :ok
      assert GraphQLWSClient.open(client) == :ok
    end

    test "reconnect with custom payload when connection failed", %{
      config: config,
      conn: conn
    } do
      test_pid = self()
      config = %{config | backoff_interval: 50}
      conn = %{conn | config: config}
      error = %SocketError{cause: :connection}

      MockDriver
      |> expect(:connect, fn ^conn ->
        {:error, error}
      end)
      |> expect(:connect, fn ^conn ->
        send(test_pid, :reconnected_msg)
        {:ok, conn}
      end)

      client = start_supervised!({GraphQLWSClient, config})

      assert GraphQLWSClient.open_with(client, @init_payload) == {:error, error}
      assert_receive :reconnected_msg
    end

    test "reconnect with custom payload when disconnected unexpectedly", %{
      config: config,
      conn: conn
    } do
      test_pid = self()
      error = %SocketError{cause: :closed}

      MockDriver
      |> expect(:connect, fn ^conn ->
        send(self(), :next_msg)
        {:ok, conn}
      end)
      |> expect(:parse_message, fn ^conn, :next_msg -> {:error, error} end)
      |> expect(:disconnect, fn ^conn -> :ok end)
      |> expect(:connect, fn ^conn ->
        send(test_pid, :reconnected_msg)
        {:ok, conn}
      end)

      client = start_supervised!({GraphQLWSClient, config})

      assert GraphQLWSClient.open_with(client, @init_payload) == :ok
      assert_receive :reconnected_msg
    end
  end

  describe "open_with!/1" do
    @init_payload %{"foo" => "bar"}

    setup do
      config = %{@config | connect_on_start: false}
      conn = %{@conn | config: config, init_payload: @init_payload}
      {:ok, config: config, conn: conn}
    end

    test "success", %{config: config, conn: conn} do
      expect(MockDriver, :connect, fn ^conn ->
        {:ok, conn}
      end)

      client = start_supervised!({GraphQLWSClient, config})

      assert GraphQLWSClient.connected?(client) == false
      assert GraphQLWSClient.open_with!(client, @init_payload) == :ok
      assert GraphQLWSClient.connected?(client) == true
    end

    test "error", %{config: config, conn: conn} do
      error = %SocketError{cause: :timeout}

      expect(MockDriver, :connect, fn ^conn ->
        {:error, error}
      end)

      client = start_supervised!({GraphQLWSClient, config})

      assert_raise SocketError, Exception.message(error), fn ->
        GraphQLWSClient.open_with!(client, @init_payload)
      end
    end
  end

  describe "close/1" do
    test "success" do
      MockDriver
      |> expect(:connect, fn @conn -> {:ok, @conn} end)
      |> expect(:disconnect, fn @conn -> :ok end)

      client = start_supervised!({GraphQLWSClient, @config})

      assert GraphQLWSClient.close(client) == :ok
    end
  end

  describe "query/3" do
    test "success" do
      test_pid = self()
      payload = %{"foo" => "bar"}

      MockDriver
      |> expect(:connect, fn @conn -> {:ok, @conn} end)
      |> expect(:push_message, fn @conn,
                                  %Message{
                                    type: :subscribe,
                                    id: id,
                                    payload: %{
                                      query: @query,
                                      variables: @variables
                                    }
                                  } ->
        send(self(), {:next_msg, id})
        :ok
      end)
      |> expect(:parse_message, fn @conn, {:next_msg, id} ->
        send(self(), {:complete_msg, id})
        {:ok, %Message{type: :next, id: id, payload: payload}}
      end)
      |> expect(:parse_message, fn @conn, {:complete_msg, id} ->
        send(test_pid, :completed_msg)
        {:ok, %Message{type: :complete, id: id}}
      end)

      client = start_supervised!({GraphQLWSClient, @config})

      assert GraphQLWSClient.query(client, @query, @variables) == {:ok, payload}

      # the subscription is only removed after the complete message is received,
      # this may happen after the client already replied to the query function
      assert_receive :completed_msg
    end

    test "query error" do
      test_pid = self()
      errors = [%{"message" => "Something went wrong"}]

      MockDriver
      |> expect(:connect, fn @conn -> {:ok, @conn} end)
      |> expect(:push_message, fn @conn, %Message{id: id} ->
        send(self(), {:next_msg, id})
        :ok
      end)
      |> expect(:parse_message, fn @conn, {:next_msg, id} ->
        send(self(), {:complete_msg, id})
        {:ok, %Message{type: :error, id: id, payload: errors}}
      end)
      |> expect(:parse_message, fn @conn, {:complete_msg, id} ->
        send(test_pid, :completed_msg)
        {:ok, %Message{type: :complete, id: id}}
      end)

      client = start_supervised!({GraphQLWSClient, @config})

      assert GraphQLWSClient.query(client, @query, @variables) ==
               {:error, %QueryError{errors: errors}}

      # the subscription is only removed after the complete message is received,
      # this may happen after the client already replied to the query function
      assert_receive :completed_msg
    end

    test "not connected" do
      config = %{@config | connect_on_start: false}
      client = start_supervised!({GraphQLWSClient, config})

      assert GraphQLWSClient.query(client, @query, @variables) ==
               {:error, %SocketError{cause: :closed}}
    end

    test "timeout" do
      test_pid = self()
      config = %{@config | query_timeout: 200}
      conn = %{@conn | config: config}

      MockDriver
      |> expect(:connect, fn _ -> {:ok, conn} end)
      |> expect(:push_message, fn _, %Message{id: id} ->
        send(test_pid, {:query_id, id})
        :ok
      end)
      |> expect(:push_message, fn _, %Message{id: id, type: :complete} ->
        send(test_pid, {:timed_out_query_id, id})
        :ok
      end)

      client = start_supervised!({GraphQLWSClient, config})

      assert GraphQLWSClient.query(client, @query, @variables) ==
               {:error, %SocketError{cause: :timeout}}

      assert_received {:query_id, query_id}
      assert_received {:timed_out_query_id, ^query_id}
    end

    test "disconnect on parse error" do
      error = %SocketError{cause: :critical_error}

      MockDriver
      |> expect(:connect, fn @conn -> {:ok, @conn} end)
      |> expect(:push_message, fn @conn, _msg ->
        send(self(), :next_msg)
        :ok
      end)
      |> expect(:parse_message, fn @conn, :next_msg ->
        {:error, error}
      end)
      |> expect(:disconnect, fn @conn -> :ok end)

      client = start_supervised!({GraphQLWSClient, @config})

      assert GraphQLWSClient.query(client, @query, @variables) ==
               {:error, error}
    end

    test "reply when socket goes down" do
      pid = spawn(fn -> Process.sleep(:infinity) end)

      conn = %{@conn | pid: pid}

      MockDriver
      |> expect(:connect, fn @conn -> {:ok, conn} end)
      |> expect(:push_message, fn ^conn, _msg ->
        # simulate an unexpected socket shutdown
        Process.exit(pid, :kill)
        :ok
      end)
      |> expect(:disconnect, fn ^conn -> :ok end)

      client = start_supervised!({GraphQLWSClient, @config})

      assert GraphQLWSClient.query(client, @query, @variables) ==
               {:error, %SocketError{cause: :closed}}
    end

    test "reply on disconnect instruction" do
      MockDriver
      |> expect(:connect, fn @conn -> {:ok, @conn} end)
      |> expect(:push_message, fn @conn, _msg ->
        send(self(), :next_msg)
        :ok
      end)
      |> expect(:parse_message, fn @conn, :next_msg ->
        :disconnect
      end)
      |> expect(:disconnect, fn @conn -> :ok end)

      client = start_supervised!({GraphQLWSClient, @config})

      assert GraphQLWSClient.query(client, @query, @variables) ==
               {:error, %SocketError{cause: :closed}}
    end

    test "do not reply on ignored message" do
      MockDriver
      |> expect(:connect, fn @conn -> {:ok, @conn} end)
      |> expect(:push_message, fn @conn, %Message{id: id} ->
        send(self(), {:next_msg, id})
        :ok
      end)
      |> expect(:parse_message, fn @conn, {:next_msg, id} ->
        send(self(), {:next_msg, id})
        :ignore
      end)
      |> expect(:parse_message, fn @conn, {:next_msg, id} ->
        {:ok, %Message{type: :next, id: id}}
      end)

      client = start_supervised!({GraphQLWSClient, @config})

      assert {:ok, _} = GraphQLWSClient.query(client, @query, @variables)
    end
  end

  describe "query/4" do
    test "timeout" do
      test_pid = self()

      MockDriver
      |> expect(:connect, fn _ -> {:ok, @conn} end)
      |> expect(:push_message, fn _, %Message{id: id} ->
        send(test_pid, {:query_id, id})
        :ok
      end)
      |> expect(:push_message, fn _, %Message{id: id, type: :complete} ->
        send(test_pid, {:timed_out_query_id, id})
        :ok
      end)

      client = start_supervised!({GraphQLWSClient, @config})

      assert GraphQLWSClient.query(client, @query, @variables, 200) ==
               {:error, %SocketError{cause: :timeout}}

      assert_received {:query_id, query_id}
      assert_received {:timed_out_query_id, ^query_id}
    end
  end

  describe "query!/3" do
    test "success" do
      test_pid = self()
      payload = %{"foo" => "bar"}

      MockDriver
      |> expect(:connect, fn @conn -> {:ok, @conn} end)
      |> expect(:push_message, fn @conn,
                                  %Message{
                                    type: :subscribe,
                                    id: id,
                                    payload: %{
                                      query: @query,
                                      variables: @variables
                                    }
                                  } ->
        send(self(), {:next_msg, id})
        :ok
      end)
      |> expect(:parse_message, fn @conn, {:next_msg, id} ->
        send(self(), {:complete_msg, id})
        {:ok, %Message{type: :next, id: id, payload: payload}}
      end)
      |> expect(:parse_message, fn @conn, {:complete_msg, id} ->
        send(test_pid, :completed_msg)
        {:ok, %Message{type: :complete, id: id}}
      end)

      client = start_supervised!({GraphQLWSClient, @config})

      assert GraphQLWSClient.query!(client, @query, @variables) == payload

      # the subscription is only removed after the complete message is received,
      # this may happen after the client already replied to the query function
      assert_receive :completed_msg
    end

    test "query error" do
      test_pid = self()
      errors = [%{"message" => "Something went wrong"}]

      MockDriver
      |> expect(:connect, fn @conn -> {:ok, @conn} end)
      |> expect(:push_message, fn @conn, %Message{id: id} ->
        send(self(), {:next_msg, id})
        :ok
      end)
      |> expect(:parse_message, fn @conn, {:next_msg, id} ->
        send(self(), {:complete_msg, id})
        {:ok, %Message{type: :error, id: id, payload: errors}}
      end)
      |> expect(:parse_message, fn @conn, {:complete_msg, id} ->
        send(test_pid, :completed_msg)
        {:ok, %Message{type: :complete, id: id}}
      end)

      client = start_supervised!({GraphQLWSClient, @config})
      error = %QueryError{errors: errors}

      assert_raise QueryError, Exception.message(error), fn ->
        GraphQLWSClient.query!(client, @query, @variables)
      end

      # the subscription is only removed after the complete message is received,
      # this may happen after the client already replied to the query function
      assert_receive :completed_msg
    end

    test "not connected" do
      config = %{@config | connect_on_start: false}
      client = start_supervised!({GraphQLWSClient, config})
      error = %SocketError{cause: :closed}

      assert_raise SocketError, Exception.message(error), fn ->
        GraphQLWSClient.query!(client, @query, @variables)
      end
    end
  end

  describe "subscribe/4" do
    test "success" do
      test_pid = self()

      MockDriver
      |> expect(:connect, fn @conn -> {:ok, @conn} end)
      |> expect(:push_message, fn @conn,
                                  %Message{
                                    type: :subscribe,
                                    id: subscription_id,
                                    payload: %{
                                      query: @query,
                                      variables: @variables
                                    }
                                  } ->
        send(test_pid, {:added_subscription, subscription_id})
        :ok
      end)

      client = start_supervised!({GraphQLWSClient, @config})

      assert {:ok, subscription_id} =
               GraphQLWSClient.subscribe(
                 client,
                 @query,
                 @variables,
                 self()
               )

      assert_received {:added_subscription, ^subscription_id}
      assert get_state(client).listeners[subscription_id].pid == self()
    end

    test "not connected" do
      client =
        start_supervised!(
          {GraphQLWSClient, %{@config | connect_on_start: false}}
        )

      assert GraphQLWSClient.subscribe(
               client,
               @query,
               @variables,
               self()
             ) == {:error, %SocketError{cause: :closed}}
    end
  end

  describe "subscribe!/4" do
    test "success" do
      test_pid = self()

      MockDriver
      |> expect(:connect, fn @conn -> {:ok, @conn} end)
      |> expect(:push_message, fn @conn,
                                  %Message{
                                    type: :subscribe,
                                    id: subscription_id,
                                    payload: %{
                                      query: @query,
                                      variables: @variables
                                    }
                                  } ->
        send(test_pid, {:added_subscription, subscription_id})
        :ok
      end)

      client = start_supervised!({GraphQLWSClient, @config})

      subscription_id =
        GraphQLWSClient.subscribe!(
          client,
          @query,
          @variables,
          self()
        )

      assert_received {:added_subscription, ^subscription_id}
      assert get_state(client).listeners[subscription_id].pid == self()
    end

    test "not connected" do
      client =
        start_supervised!(
          {GraphQLWSClient, %{@config | connect_on_start: false}}
        )

      error = %SocketError{cause: :closed}

      assert_raise SocketError, Exception.message(error), fn ->
        GraphQLWSClient.subscribe!(
          client,
          @query,
          @variables,
          self()
        )
      end
    end
  end

  describe "unsubscribe/1" do
    test "success" do
      test_pid = self()

      MockDriver
      |> expect(:connect, fn @conn -> {:ok, @conn} end)
      |> expect(:push_message, fn @conn, %Message{type: :subscribe} -> :ok end)
      |> expect(:push_message, fn @conn,
                                  %Message{
                                    type: :complete,
                                    id: subscription_id
                                  } ->
        send(test_pid, {:removed_subscription, subscription_id})
        :ok
      end)

      client = start_supervised!({GraphQLWSClient, @config})
      subscription_id = GraphQLWSClient.subscribe!(client, @query)

      assert GraphQLWSClient.unsubscribe(client, subscription_id) == :ok
      assert_received {:removed_subscription, ^subscription_id}
      refute Map.has_key?(get_state(client).listeners, subscription_id)
    end

    test "not connected" do
      client =
        start_supervised!(
          {GraphQLWSClient, %{@config | connect_on_start: false}}
        )

      assert GraphQLWSClient.unsubscribe(client, @subscription_id) ==
               {:error, %SocketError{cause: :closed}}
    end
  end

  describe "unsubscribe!/1" do
    test "success" do
      test_pid = self()

      MockDriver
      |> expect(:connect, fn @conn -> {:ok, @conn} end)
      |> expect(:push_message, fn @conn, %Message{type: :subscribe} -> :ok end)
      |> expect(:push_message, fn @conn,
                                  %Message{
                                    type: :complete,
                                    id: subscription_id
                                  } ->
        send(test_pid, {:removed_subscription, subscription_id})
        :ok
      end)

      client = start_supervised!({GraphQLWSClient, @config})
      subscription_id = GraphQLWSClient.subscribe!(client, @query)

      assert GraphQLWSClient.unsubscribe!(client, subscription_id) == :ok
      assert_received {:removed_subscription, ^subscription_id}
      refute Map.has_key?(get_state(client).listeners, subscription_id)
    end

    test "not connected" do
      client =
        start_supervised!(
          {GraphQLWSClient, %{@config | connect_on_start: false}}
        )

      error = %SocketError{cause: :closed}

      assert_raise SocketError, Exception.message(error), fn ->
        GraphQLWSClient.unsubscribe!(client, @subscription_id)
      end
    end
  end

  describe "listener" do
    setup do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      conn = %{@conn | pid: pid}

      MockDriver
      |> expect(:connect, fn @conn -> {:ok, conn} end)
      # this is the subscribe query
      |> expect(:push_message, fn ^conn, _ -> :ok end)

      client = start_supervised!({GraphQLWSClient, @config})

      subscription_id = GraphQLWSClient.subscribe!(client, @query, @variables)

      on_exit(fn ->
        Process.exit(pid, :normal)
      end)

      {:ok, client: client, conn: conn, subscription_id: subscription_id}
    end

    test "next message", %{
      client: client,
      conn: conn,
      subscription_id: subscription_id
    } do
      result = %{"foo" => "bar"}

      expect(MockDriver, :parse_message, fn ^conn, :test_message ->
        {:ok, %Message{id: subscription_id, type: :next, payload: result}}
      end)

      send(client, :test_message)

      assert_receive %Event{
        status: :ok,
        subscription_id: ^subscription_id,
        result: ^result
      }
    end

    test "error message", %{
      client: client,
      conn: conn,
      subscription_id: subscription_id
    } do
      errors = [%{"message" => "Something went wrong"}]

      expect(MockDriver, :parse_message, fn ^conn, :test_message ->
        {:ok, %Message{id: subscription_id, type: :error, payload: errors}}
      end)

      send(client, :test_message)

      assert_receive %Event{
        status: :error,
        subscription_id: ^subscription_id,
        result: %QueryError{errors: ^errors}
      }
    end

    test "ignore message with unexpected format", %{client: client, conn: conn} do
      expect(MockDriver, :parse_message, fn ^conn, :test_message ->
        :ignore
      end)

      send(client, :test_message)

      refute_receive %Event{}
    end

    test "ignore message when not connected", %{client: client, conn: conn} do
      stub(MockDriver, :disconnect, fn ^conn -> :ok end)

      :ok = GraphQLWSClient.close(client)
      refute GraphQLWSClient.connected?(client)

      send(client, :test_message)

      refute_receive %Event{}
    end

    test "resubscribe on disconnect instruction", %{
      client: client,
      conn: conn,
      subscription_id: subscription_id
    } do
      test_pid = self()

      MockDriver
      |> expect(:parse_message, fn ^conn, :test_message -> :disconnect end)
      # reconnect
      |> expect(:disconnect, fn ^conn -> :ok end)
      |> expect(:connect, fn @conn -> {:ok, conn} end)
      # resubscribe
      |> expect(:push_message, fn ^conn,
                                  %Message{
                                    type: :complete,
                                    id: ^subscription_id
                                  } ->
        :ok
      end)
      |> expect(:push_message, fn ^conn,
                                  %Message{
                                    type: :subscribe,
                                    id: ^subscription_id,
                                    payload: %{
                                      query: @query,
                                      variables: @variables
                                    }
                                  } ->
        send(test_pid, :completed_msg)
        :ok
      end)

      listeners = get_state(client).listeners

      send(client, :test_message)

      assert_receive :completed_msg
      assert get_state(client).listeners == listeners
    end

    test "resubscribe on parse error", %{
      client: client,
      conn: conn,
      subscription_id: subscription_id
    } do
      test_pid = self()
      error = %SocketError{cause: :critical_error}

      MockDriver
      |> expect(:parse_message, fn ^conn, :test_message ->
        {:error, error}
      end)
      # reconnect
      |> expect(:disconnect, fn ^conn -> :ok end)
      |> expect(:connect, fn @conn -> {:ok, conn} end)
      # resubscribe
      |> expect(:push_message, fn ^conn,
                                  %Message{
                                    type: :complete,
                                    id: ^subscription_id
                                  } ->
        :ok
      end)
      |> expect(:push_message, fn ^conn,
                                  %Message{
                                    type: :subscribe,
                                    id: ^subscription_id,
                                    payload: %{
                                      query: @query,
                                      variables: @variables
                                    }
                                  } ->
        send(test_pid, :completed_msg)
        :ok
      end)

      listeners = get_state(client).listeners

      send(client, :test_message)

      assert_receive :completed_msg
      assert get_state(client).listeners == listeners
    end

    test "resubscribe when socket goes down", %{
      client: client,
      conn: conn,
      subscription_id: subscription_id
    } do
      test_pid = self()
      new_pid = spawn(fn -> Process.sleep(:infinity) end)
      new_conn = %{@conn | pid: new_pid}

      on_exit(fn ->
        Process.exit(new_pid, :normal)
      end)

      MockDriver
      # reconnect
      |> expect(:disconnect, fn ^conn -> :ok end)
      |> expect(:connect, fn @conn -> {:ok, new_conn} end)
      # resubscribe
      |> expect(:push_message, fn ^new_conn,
                                  %Message{
                                    type: :complete,
                                    id: ^subscription_id
                                  } ->
        :ok
      end)
      |> expect(:push_message, fn ^new_conn,
                                  %Message{
                                    type: :subscribe,
                                    id: ^subscription_id,
                                    payload: %{
                                      query: @query,
                                      variables: @variables
                                    }
                                  } ->
        send(test_pid, :completed_msg)
        :ok
      end)

      listeners = get_state(client).listeners

      Process.exit(conn.pid, :kill)

      assert_receive :completed_msg
      assert get_state(client).listeners == listeners
    end
  end

  describe "custom listener" do
    setup do
      listener = spawn(fn -> Process.sleep(:infinity) end)

      MockDriver
      |> expect(:connect, fn @conn -> {:ok, @conn} end)
      |> expect(:push_message, fn @conn, _ -> :ok end)

      client = start_supervised!({GraphQLWSClient, @config})

      subscription_id =
        GraphQLWSClient.subscribe!(client, @query, @variables, listener)

      on_exit(fn ->
        Process.exit(listener, :normal)
      end)

      {:ok,
       client: client, listener: listener, subscription_id: subscription_id}
    end

    test "remove listener when listener process goes down", %{
      client: client,
      listener: listener,
      subscription_id: subscription_id
    } do
      assert capture_log(fn ->
               Process.exit(listener, :kill)

               # wait until the subscription is actually removed
               Process.sleep(100)
             end) =~
               "Subscription #{subscription_id} removed as listener " <>
                 "process #{inspect(listener)} went down"

      refute Map.has_key?(get_state(client).listeners, subscription_id)
    end
  end

  defp get_state(client) do
    :sys.get_state(client).mod_state
  end
end
