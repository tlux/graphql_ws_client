defmodule GraphQLWSClient.ConfigTest do
  use ExUnit.Case, async: true

  alias GraphQLWSClient.Config

  describe "new/1" do
    test "minimal config" do
      assert Config.new(host: "example.com", port: 80) == %Config{
               backoff_interval: 3000,
               connect_timeout: 5000,
               driver: {GraphQLWSClient.Drivers.Websocket, []},
               host: "example.com",
               init_payload: nil,
               init_timeout: 5000,
               json_library: Jason,
               path: "/",
               port: 80,
               upgrade_timeout: 5000
             }
    end

    test "minimal config with ws:// URL" do
      assert Config.new(url: "ws://example.com") == %Config{
               host: "example.com",
               port: 80,
               path: "/"
             }

      assert Config.new(url: "ws://example.com:8080") == %Config{
               host: "example.com",
               port: 8080,
               path: "/"
             }

      assert Config.new(url: "ws://example.com/subscriptions") == %Config{
               host: "example.com",
               port: 80,
               path: "/subscriptions"
             }
    end

    test "minimal config with wss:// URL" do
      assert Config.new(url: "wss://example.com") == %Config{
               host: "example.com",
               port: 443,
               path: "/"
             }
    end

    test "full config" do
      opts = [
        backoff_interval: 1000,
        connect_timeout: 2000,
        driver: {SomeDriver, []},
        host: "example.com",
        init_payload: %{"foo" => "bar"},
        init_timeout: 3000,
        json_library: SomeJSONLibrary,
        path: "/subscriptions",
        port: 8080,
        upgrade_timeout: 4000
      ]

      assert Config.new(opts) == struct!(Config, opts)
    end

    test "error when URL has empty scheme" do
      assert_raise ArgumentError, "URL has no protocol", fn ->
        Config.new(url: "example.com")
      end
    end

    test "error when URL has invalid protocol" do
      assert_raise ArgumentError,
                   "URL has invalid protocol: http (allowed: ws, wss)",
                   fn ->
                     Config.new(url: "http://example.com")
                   end
    end

    test "error when URL has empty host" do
      assert_raise ArgumentError, "URL has empty host", fn ->
        Config.new(url: "ws:///subscriptions")
      end
    end

    test "error on invalid key" do
      assert_raise KeyError, "key :foo not found", fn ->
        Config.new(foo: "bar")
      end
    end

    test "error when host missing" do
      assert_raise ArgumentError,
                   ~r/the following keys must also be given/,
                   fn ->
                     Config.new(port: 8080)
                   end
    end

    test "error when port missing" do
      assert_raise ArgumentError,
                   ~r/the following keys must also be given/,
                   fn ->
                     Config.new(host: "example.com")
                   end
    end
  end
end
