defmodule GraphQLWSClientTest do
  use ExUnit.Case

  import Liveness
  import Mox

  alias GraphQLWSClient.{Config, WSClientMock}

  setup :set_mox_from_context
  setup :verify_on_exit!

  @config %Config{
    backoff_interval: 1000,
    connect_timeout: 500,
    host: "example.com",
    init_payload: %{"token" => "__token__"},
    init_timeout: 2000,
    json_library: Jason,
    path: "/subscriptions",
    port: 1234,
    upgrade_timeout: 1500,
    ws_client: WSClientMock
  }

  describe "start_link/2" do
    test "success" do
      ws_pid = spawn(fn -> nil end)
      stream_ref = make_ref()

      init_payload =
        Jason.encode!(%{
          "type" => "connection_init",
          "payload" => @config.init_payload
        })

      WSClientMock
      |> expect(:open, fn 'example.com', 1234, %{protocols: [:http]} ->
        {:ok, ws_pid}
      end)
      |> expect(:await_up, fn ^ws_pid, 500 ->
        {:ok, :http}
      end)
      |> expect(:ws_upgrade, fn ^ws_pid, "/subscriptions" ->
        send(
          self(),
          {:gun_upgrade, ws_pid, stream_ref, ["websocket"], nil}
        )

        stream_ref
      end)
      |> expect(:ws_send, fn ^ws_pid, ^stream_ref, {:text, ^init_payload} ->
        send(
          self(),
          {:gun_ws, ws_pid, stream_ref,
           {:text, Jason.encode!(%{"type" => "connection_ack"})}}
        )

        :ok
      end)

      # |> expect(:close, fn ^ws_pid -> :ok end)

      assert {:ok, client} = start_supervised({GraphQLWSClient, @config})

      assert eventually(fn ->
               GraphQLWSClient.connected?(client)
             end)

      IO.inspect(client)
    end
  end
end
