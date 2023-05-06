defmodule GraphQLWSClient.Drivers.GunTest do
  use ExUnit.Case

  import Mox

  alias GraphQLWSClient.SocketError
  alias GraphQLWSClient.Config
  alias GraphQLWSClient.Conn
  alias GraphQLWSClient.Drivers.Gun
  alias GraphQLWSClient.WSClientMock

  @config Config.new(
            connect_timeout: 200,
            init_payload: %{"foo" => "bar"},
            init_timeout: 200,
            url: "ws://example.com/subscriptions",
            upgrade_timeout: 200
          )

  @opts Gun.init(%{adapter: WSClientMock})
  @conn %Conn{config: @config, driver: Gun, opts: @opts}

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    pid = spawn_link(fn -> Process.sleep(:infinity) end)
    stream_ref = make_ref()
    {:ok, pid: pid, stream_ref: stream_ref}
  end

  describe "init/1" do
    test "default adapter" do
      assert Gun.init(%{}) == %{adapter: :gun}
    end

    test "custom adapter" do
      assert Gun.init(%{adapter: WSClientMock}) == %{adapter: WSClientMock}
    end
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

      assert Gun.connect(@conn) ==
               {:ok,
                %{
                  @conn
                  | data: %{stream_ref: stream_ref},
                    pid: pid
                }}
    end

    test "connection error" do
      expect(WSClientMock, :open, fn _, _, _ ->
        {:error, :something_went_wrong}
      end)

      assert Gun.connect(@conn) ==
               {:error,
                %SocketError{
                  cause: :connect,
                  details: %{reason: :something_went_wrong}
                }}
    end

    test "timeout awaiting connection", %{pid: pid} do
      WSClientMock
      |> expect(:open, fn _, _, _ -> {:ok, pid} end)
      |> expect(:await_up, fn _, _ -> {:error, :timeout} end)

      assert Gun.connect(@conn) == {:error, %SocketError{cause: :timeout}}
    end

    test "connection went down while awaiting connection", %{pid: pid} do
      WSClientMock
      |> expect(:open, fn _, _, _ -> {:ok, pid} end)
      |> expect(:await_up, fn _, _ -> {:error, {:down, nil}} end)

      assert Gun.connect(@conn) == {:error, %SocketError{cause: :closed}}
    end

    test "timeout awaiting upgrade", %{pid: pid, stream_ref: stream_ref} do
      WSClientMock
      |> expect(:open, fn _, _, _ -> {:ok, pid} end)
      |> expect(:await_up, fn _, _ -> {:ok, :http} end)
      |> expect(:ws_upgrade, fn _, _ -> stream_ref end)

      assert Gun.connect(@conn) == {:error, %SocketError{cause: :timeout}}
    end

    test "timeout awaiting connection ack", %{pid: pid, stream_ref: stream_ref} do
      WSClientMock
      |> expect(:open, fn _, _, _ -> {:ok, pid} end)
      |> expect(:await_up, fn _, _ -> {:ok, :http} end)
      |> expect(:ws_upgrade, fn _, _ ->
        send(self(), {:gun_upgrade, pid, stream_ref, ["websocket"], nil})
        stream_ref
      end)
      |> expect(:ws_send, fn _, _, {:text, @init_payload} -> :ok end)

      assert Gun.connect(@conn) == {:error, %SocketError{cause: :timeout}}
    end

    test "unexpected text result for connection ack", %{
      pid: pid,
      stream_ref: stream_ref
    } do
      WSClientMock
      |> expect(:open, fn _, _, _ -> {:ok, pid} end)
      |> expect(:await_up, fn _, _ -> {:ok, :http} end)
      |> expect(:ws_upgrade, fn _, _ ->
        send(self(), {:gun_upgrade, pid, stream_ref, ["websocket"], nil})
        stream_ref
      end)
      |> expect(:ws_send, fn _, _, {:text, @init_payload} ->
        send(self(), {:gun_ws, pid, stream_ref, {:text, "__invalid__"}})
        :ok
      end)

      assert Gun.connect(@conn) ==
               {:error, %SocketError{cause: :unexpected_result}}
    end

    test "unexpected non-text result for connection ack", %{
      pid: pid,
      stream_ref: stream_ref
    } do
      WSClientMock
      |> expect(:open, fn _, _, _ -> {:ok, pid} end)
      |> expect(:await_up, fn _, _ -> {:ok, :http} end)
      |> expect(:ws_upgrade, fn _, _ ->
        send(self(), {:gun_upgrade, pid, stream_ref, ["websocket"], nil})
        stream_ref
      end)
      |> expect(:ws_send, fn _, _, {:text, @init_payload} ->
        send(self(), {:gun_ws, pid, stream_ref, "__invalid__"})
        :ok
      end)

      assert Gun.connect(@conn) ==
               {:error, %SocketError{cause: :unexpected_result}}
    end

    test "closed on connection ack", %{pid: pid, stream_ref: stream_ref} do
      WSClientMock
      |> expect(:open, fn _, _, _ -> {:ok, pid} end)
      |> expect(:await_up, fn _, _ -> {:ok, :http} end)
      |> expect(:ws_upgrade, fn _, _ ->
        send(self(), {:gun_upgrade, pid, stream_ref, ["websocket"], nil})
        stream_ref
      end)
      |> expect(:ws_send, fn _, _, {:text, @init_payload} ->
        send(
          self(),
          {:gun_ws, pid, stream_ref, {:close, 123, "Something went wrong"}}
        )

        :ok
      end)

      assert Gun.connect(@conn) ==
               {:error,
                %SocketError{
                  cause: :closed,
                  details: %{code: 123, payload: "Something went wrong"}
                }}
    end

    test "error on connection ack", %{pid: pid, stream_ref: stream_ref} do
      WSClientMock
      |> expect(:open, fn _, _, _ -> {:ok, pid} end)
      |> expect(:await_up, fn _, _ -> {:ok, :http} end)
      |> expect(:ws_upgrade, fn _, _ ->
        send(self(), {:gun_upgrade, pid, stream_ref, ["websocket"], nil})
        stream_ref
      end)
      |> expect(:ws_send, fn _, _, {:text, @init_payload} ->
        send(self(), {:gun_error, pid, stream_ref, "Something went wrong"})
        :ok
      end)

      assert Gun.connect(@conn) ==
               {:error,
                %SocketError{
                  cause: :critical_error,
                  details: %{reason: "Something went wrong"}
                }}
    end
  end

  describe "disconnect/1" do
    # TODO
  end

  describe "push_message/2" do
    # TODO
  end

  describe "parse_message/2" do
    # TODO
  end
end
