defmodule GraphQLWSClientTest do
  use ExUnit.Case

  import Mox

  alias GraphQLWSClient.{Config, SocketError, WSClientMock}

  @config %Config{
    backoff_interval: 1000,
    connect_timeout: 500,
    connect_on_start: false,
    host: "example.com",
    init_payload: %{"token" => "__token__"},
    init_timeout: 2000,
    json_library: Jason,
    path: "/subscriptions",
    port: 1234,
    upgrade_timeout: 1500,
    ws_client: WSClientMock
  }

  setup do
    stub(WSClientMock, :close, fn _ -> :ok end)
    :ok
  end

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    ws_pid = spawn_link(fn -> Process.sleep(:infinity) end)
    stream_ref = make_ref()

    {:ok, ws_pid: ws_pid, stream_ref: stream_ref}
  end

  describe "open/1" do
    test "success", %{ws_pid: ws_pid, stream_ref: stream_ref} do
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

      assert {:ok, client} = start_supervised({GraphQLWSClient, @config})
      assert GraphQLWSClient.connected?(client) == false
      assert GraphQLWSClient.open(client) == :ok
      assert GraphQLWSClient.connected?(client) == true
    end

    test "upgrade timeout", %{ws_pid: ws_pid, stream_ref: stream_ref} do
      WSClientMock
      |> expect(:open, fn _, _, _ -> {:ok, ws_pid} end)
      |> expect(:await_up, fn ^ws_pid, _ -> {:ok, :http} end)
      |> expect(:ws_upgrade, fn ^ws_pid, _ -> stream_ref end)

      config = %{@config | upgrade_timeout: 200}

      assert {:ok, client} = start_supervised({GraphQLWSClient, config})

      assert GraphQLWSClient.open(client) ==
               {:error, %SocketError{cause: :timeout}}
    end
  end
end
