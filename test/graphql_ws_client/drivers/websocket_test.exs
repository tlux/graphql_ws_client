defmodule GraphQLWSClient.Drivers.WebsocketTest do
  use ExUnit.Case

  import Mox

  alias GraphQLWSClient.Config
  alias GraphQLWSClient.Conn
  alias GraphQLWSClient.Driver
  alias GraphQLWSClient.Drivers.Websocket
  alias GraphQLWSClient.WSClientMock

  @config Config.new(
            connect_timeout: 200,
            driver: {Websocket, adapter: WSClientMock},
            init_payload: %{"foo" => "bar"},
            init_timeout: 200,
            url: "ws://example.com/subscriptions"
          )

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    pid = spawn_link(fn -> Process.sleep(:infinity) end)
    stream_ref = make_ref()
    {:ok, pid: pid, stream_ref: stream_ref}
  end

  describe "connect/1" do
    @init_payload Jason.encode!(%{
                    "type" => "connection_init",
                    "payload" => @config.init_payload
                  })

    @ack_payload Jason.encode!(%{"type" => "connection_ack"})

    test "success", %{pid: pid, stream_ref: stream_ref} do
      WSClientMock
      |> expect(:open, fn 'example.com', 80, %{protocols: [:http]} ->
        {:ok, pid}
      end)
      |> expect(:await_up, fn ^pid, 200 ->
        {:ok, :http}
      end)
      |> expect(:ws_upgrade, fn ^pid, "/subscriptions" ->
        send(self(), {:gun_upgrade, pid, stream_ref, ["websocket"], nil})
        stream_ref
      end)
      |> expect(:ws_send, fn ^pid, ^stream_ref, {:text, @init_payload} ->
        send(self(), {:gun_ws, pid, stream_ref, {:text, @ack_payload}})
        :ok
      end)

      assert Driver.connect(@config) ==
               {:ok,
                %Conn{
                  config: @config,
                  opts: %{adapter: WSClientMock},
                  pid: pid,
                  stream_ref: stream_ref
                }}
    end
  end

  describe "disconnect/1" do
    # TODO
  end

  describe "push_message/2" do
    # TODO
  end

  describe "handle_message/2" do
    # TODO
  end
end
