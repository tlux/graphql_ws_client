defmodule GraphQLWSClientTest do
  use ExUnit.Case

  import ExUnit.CaptureLog
  import Mox

  alias GraphQLWSClient.{Config, Conn, SocketError}
  alias GraphQLWSClient.Drivers.Mock, as: MockDriver

  @config %Config{
    backoff_interval: 1000,
    connect_timeout: 500,
    driver: {GraphQLWSClient.Drivers.Mock, []},
    host: "example.com",
    init_payload: %{"token" => "__token__"},
    init_timeout: 2000,
    json_library: Jason,
    path: "/subscriptions",
    port: 1234,
    upgrade_timeout: 1500
  }

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    pid = spawn_link(fn -> Process.sleep(:infinity) end)
    stream_ref = make_ref()

    {:ok, conn: %Conn{json_library: Jason, pid: pid, stream_ref: stream_ref}}
  end

  describe "start_link/1" do
    test "success", %{conn: conn} do
      expect(MockDriver, :connect, fn @config ->
        {:ok, conn}
      end)

      assert {:ok, client} = start_supervised({GraphQLWSClient, @config})
      assert GraphQLWSClient.connected?(client) == true
    end

    test "error" do
      error = %SocketError{cause: :timeout}

      expect(MockDriver, :connect, fn @config ->
        {:error, error}
      end)

      assert capture_log(fn ->
               start_supervised!({GraphQLWSClient, @config})

               # wait a little bit until the connection fails
               Process.sleep(100)
             end) =~ Exception.message(error)
    end
  end

  describe "open/1" do
    setup do
      {:ok, config: %{@config | connect_on_start: false}}
    end

    test "success", %{config: config, conn: conn} do
      expect(MockDriver, :connect, fn ^config ->
        {:ok, conn}
      end)

      assert {:ok, client} = start_supervised({GraphQLWSClient, config})
      assert GraphQLWSClient.connected?(client) == false
      assert GraphQLWSClient.open(client) == :ok
      assert GraphQLWSClient.connected?(client) == true
    end

    test "error", %{config: config} do
      config = %{config | upgrade_timeout: 200}
      error = %SocketError{cause: :timeout}

      expect(MockDriver, :connect, fn ^config ->
        {:error, error}
      end)

      assert {:ok, client} = start_supervised({GraphQLWSClient, config})
      assert GraphQLWSClient.open(client) == {:error, error}
    end
  end
end
