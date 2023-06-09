defmodule GraphQLWSClient.DriverTest do
  use ExUnit.Case, async: true

  import Mox

  alias GraphQLWSClient.Config
  alias GraphQLWSClient.Conn
  alias GraphQLWSClient.Driver
  alias GraphQLWSClient.Drivers.{Mock, MockWithoutInit}
  alias GraphQLWSClient.Message

  setup :verify_on_exit!

  @init_payload %{"foo" => "bar"}
  @config %Config{host: "example.com", port: 80}
  @conn %Conn{config: @config, driver: Mock, init_payload: @init_payload}

  describe "connect/2" do
    @opts %{foo: "bar"}

    test "without driver options, with init function" do
      config = %{@config | driver: Mock}

      conn = %Conn{
        config: config,
        driver: Mock,
        init_payload: @init_payload,
        opts: @opts
      }

      Mock
      |> expect(:init, fn opts when map_size(opts) == 0 -> @opts end)
      |> expect(:connect, fn ^conn -> {:ok, conn} end)

      assert Driver.connect(config, @init_payload) == {:ok, conn}
    end

    test "without driver options, without init function" do
      config = %{@config | driver: MockWithoutInit}

      conn = %Conn{
        config: config,
        driver: MockWithoutInit,
        init_payload: @init_payload
      }

      expect(MockWithoutInit, :connect, fn ^conn -> {:ok, conn} end)

      assert Driver.connect(config, @init_payload) == {:ok, conn}
    end

    test "with driver options, with init function" do
      config = %{@config | driver: {Mock, @opts}}
      updated_opts = Map.put(@opts, :baz, 1234)

      conn = %Conn{
        config: config,
        driver: Mock,
        init_payload: @init_payload,
        opts: updated_opts
      }

      Mock
      |> expect(:init, fn @opts -> updated_opts end)
      |> expect(:connect, fn ^conn -> {:ok, conn} end)

      assert Driver.connect(config, @init_payload) == {:ok, conn}
    end

    test "with driver options, without init function" do
      config = %{@config | driver: {MockWithoutInit, @opts}}

      conn = %Conn{
        config: config,
        driver: MockWithoutInit,
        init_payload: @init_payload,
        opts: @opts
      }

      expect(MockWithoutInit, :connect, fn ^conn -> {:ok, conn} end)

      assert Driver.connect(config, @init_payload) == {:ok, conn}
    end
  end

  describe "disconnect/1" do
    test "delegate to driver" do
      expect(Mock, :disconnect, fn @conn -> :ok end)

      assert Driver.disconnect(@conn) == :ok
    end
  end

  describe "push_message/1" do
    test "delegate to driver" do
      msg = %Message{type: :subscribe, id: "__id__", payload: "__payload__"}

      expect(Mock, :push_message, fn @conn, ^msg -> :ok end)

      assert Driver.push_message(@conn, msg) == :ok
    end
  end

  describe "parse_message/1" do
    test "delegate to driver" do
      msg = "__message__"

      expect(Mock, :parse_message, fn @conn, ^msg -> :ok end)

      assert Driver.parse_message(@conn, msg) == :ok
    end
  end
end
