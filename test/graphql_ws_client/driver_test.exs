defmodule GraphQLWSClient.DriverTest do
  use ExUnit.Case, async: true

  import Mox

  # alias GraphQLWSClient.Message
  # alias GraphQLWSClient.Conn
  # alias GraphQLWSClient.Config
  # alias GraphQLWSClient.Driver
  # alias GraphQLWSClient.Drivers.{Mock, MockWithoutInit}

  setup :verify_on_exit!

  # @config %Config{host: "example.com", port: 80}
  # @conn %Conn{config: @config, driver: MockDriver, opts: %{}}

  describe "connect/1" do
    test "delegate to driver with init"

    test "delegate to driver without init"
  end

  describe "disconnect/1" do
    test "delegate to driver"
  end

  describe "push_message/1" do
    test "delegate to driver"
  end

  describe "parse_message/1" do
    test "delegate to driver"
  end
end
