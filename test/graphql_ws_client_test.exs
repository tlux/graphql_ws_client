defmodule GraphQLWSClientTest do
  use ExUnit.Case

  import ExUnit.CaptureLog
  import Mox

  alias GraphQLWSClient.{Config, Conn, Event, Message, QueryError, SocketError}
  alias GraphQLWSClient.Drivers.MockWithoutInit, as: MockDriver

  @opts [
    backoff_interval: 1000,
    connect_timeout: 500,
    driver: MockDriver,
    host: "example.com",
    init_payload: %{"token" => "__token__"},
    init_timeout: 2000,
    json_library: Jason,
    path: "/subscriptions",
    port: 1234,
    upgrade_timeout: 1500
  ]

  @config struct!(Config, @opts)
  @conn %Conn{config: @config, driver: MockDriver}
  @subscription_id "__subscription_id__"
  @subscription_query "subscription Foo { foo { bar } }"
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

  describe "close/1" do
    # TODO
  end

  describe "query/3" do
    # TODO
  end

  describe "query!/3" do
    # TODO
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
                                      query: @subscription_query,
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
                 @subscription_query,
                 @variables,
                 self()
               )

      assert_received {:added_subscription, ^subscription_id}
      assert get_state(client).listeners[subscription_id] == self()
    end

    test "not connected" do
      client =
        start_supervised!(
          {GraphQLWSClient, %{@config | connect_on_start: false}}
        )

      assert GraphQLWSClient.subscribe(
               client,
               @subscription_query,
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
                                      query: @subscription_query,
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
          @subscription_query,
          @variables,
          self()
        )

      assert_received {:added_subscription, ^subscription_id}
      assert get_state(client).listeners[subscription_id] == self()
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
          @subscription_query,
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
      subscription_id = GraphQLWSClient.subscribe!(client, @subscription_query)

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
      subscription_id = GraphQLWSClient.subscribe!(client, @subscription_query)

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
      MockDriver
      |> expect(:connect, fn @conn -> {:ok, @conn} end)
      |> expect(:push_message, fn @conn, _ -> :ok end)

      client = start_supervised!({GraphQLWSClient, @config})

      subscription_id =
        GraphQLWSClient.subscribe!(client, @subscription_query, @variables)

      {:ok, client: client, subscription_id: subscription_id}
    end

    test "receive result", %{client: client, subscription_id: subscription_id} do
      result = %{"foo" => "bar"}

      expect(MockDriver, :parse_message, fn @conn, :test_message ->
        {:ok, %Message{id: subscription_id, type: :next, payload: result}}
      end)

      send(client, :test_message)

      assert_receive %Event{
        subscription_id: ^subscription_id,
        result: ^result,
        error: nil
      }
    end

    test "receive error", %{client: client, subscription_id: subscription_id} do
      errors = [%{"message" => "Something went wrong"}]

      expect(MockDriver, :parse_message, fn @conn, :test_message ->
        {:ok, %Message{id: subscription_id, type: :error, payload: errors}}
      end)

      send(client, :test_message)

      assert_receive %Event{
        subscription_id: ^subscription_id,
        result: nil,
        error: %QueryError{errors: ^errors}
      }
    end
  end

  defp get_state(client) do
    :sys.get_state(client).mod_state
  end
end
