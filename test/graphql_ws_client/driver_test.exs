defmodule GraphQLWSClient.DriverTest do
  use ExUnit.Case, async: true

  import Mox

  alias GraphQLWSClient.Conn
  alias GraphQLWSClient.Config
  alias GraphQLWSClient.Driver
  alias GraphQLWSClient.Drivers.Mock, as: MockDriver

  setup :verify_on_exit!

  @config %Config{
    driver: nil,
    host: "example.com",
    port: 80
  }

  describe "connect/1" do
    test "driver without options" do
      config = %{@config | driver: MockDriver}

      conn = %Conn{config: config, opts: %{}}
      updated_conn = %{conn | pid: self(), stream_ref: make_ref()}

      expect(MockDriver, :connect, fn ^conn ->
        {:ok, updated_conn}
      end)

      assert {:ok, ^updated_conn} = Driver.connect(config)
    end

    test "driver with options" do
      config = %{@config | driver: {MockDriver, foo: "bar", baz: 123}}

      conn = %Conn{config: config, opts: %{foo: "bar", baz: 123}}
      updated_conn = %{conn | pid: self(), stream_ref: make_ref()}

      expect(MockDriver, :connect, fn ^conn ->
        {:ok, updated_conn}
      end)

      assert {:ok, ^updated_conn} = Driver.connect(config)
    end
  end

  describe "disconnect/1" do
    @conn %Conn{config: @config, opts: %{}}

    test "driver without options" do
      conn = %{@conn | config: %{@config | driver: MockDriver}}

      expect(MockDriver, :disconnect, fn ^conn -> :ok end)

      assert Driver.disconnect(conn) == :ok
    end

    test "driver with options" do
      conn = %{@conn | config: %{@config | driver: {MockDriver, []}}}

      expect(MockDriver, :disconnect, fn ^conn -> :ok end)

      assert Driver.disconnect(conn) == :ok
    end
  end
end
