defmodule GraphQLWSClient.Drivers.GunTest do
  use ExUnit.Case, async: true

  import Mox

  alias GraphQLWSClient.Config
  alias GraphQLWSClient.Conn
  alias GraphQLWSClient.Drivers.Gun
  alias GraphQLWSClient.Message
  alias GraphQLWSClient.SocketError
  alias GraphQLWSClient.WSClientMock

  @config Config.new(
            init_payload: %{"foo" => "bar"},
            url: "ws://example.com/subscriptions"
          )

  @opts Gun.init(%{
          ack_timeout: 200,
          adapter: WSClientMock,
          connect_options: %{connect_timeout: 250},
          upgrade_timeout: 300
        })

  @conn %Conn{config: @config, driver: Gun, opts: @opts}

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    pid = spawn_link(fn -> Process.sleep(:infinity) end)
    stream_ref = make_ref()
    {:ok, pid: pid, stream_ref: stream_ref}
  end

  describe "init/1" do
    test "min options" do
      assert Gun.init(%{}) == %Gun.Opts{adapter: :gun, json_library: Jason}
    end

    test "max options" do
      assert Gun.init(%{adapter: WSClientMock, json_library: SomeJSONLibrary}) ==
               %Gun.Opts{
                 adapter: WSClientMock,
                 json_library: SomeJSONLibrary
               }
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
      |> expect(:await_up, fn ^pid, 250 ->
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
      |> expect(:close, fn ^pid -> :ok end)

      assert Gun.connect(@conn) == {:error, %SocketError{cause: :timeout}}
    end

    test "connection went down while awaiting connection", %{pid: pid} do
      WSClientMock
      |> expect(:open, fn _, _, _ -> {:ok, pid} end)
      |> expect(:await_up, fn _, _ -> {:error, {:down, nil}} end)
      |> expect(:close, fn ^pid -> :ok end)

      assert Gun.connect(@conn) == {:error, %SocketError{cause: :closed}}
    end

    test "timeout awaiting upgrade", %{pid: pid, stream_ref: stream_ref} do
      WSClientMock
      |> expect(:open, fn _, _, _ -> {:ok, pid} end)
      |> expect(:await_up, fn _, _ -> {:ok, :http} end)
      |> expect(:ws_upgrade, fn _, _ -> stream_ref end)
      |> expect(:close, fn ^pid -> :ok end)

      assert Gun.connect(@conn) == {:error, %SocketError{cause: :timeout}}
    end

    test "unexpected status awaiting upgrade", %{
      pid: pid,
      stream_ref: stream_ref
    } do
      code = 200

      WSClientMock
      |> expect(:open, fn _, _, _ -> {:ok, pid} end)
      |> expect(:await_up, fn _, _ -> {:ok, :http} end)
      |> expect(:ws_upgrade, fn _, _ ->
        send(self(), {:gun_response, pid, stream_ref, nil, code, nil})
        stream_ref
      end)
      |> expect(:close, fn ^pid -> :ok end)

      assert Gun.connect(@conn) ==
               {:error,
                %SocketError{cause: :unexpected_status, details: %{code: code}}}
    end

    test "error awaiting upgrade", %{
      pid: pid,
      stream_ref: stream_ref
    } do
      reason = "Something went wrong"

      WSClientMock
      |> expect(:open, fn _, _, _ -> {:ok, pid} end)
      |> expect(:await_up, fn _, _ -> {:ok, :http} end)
      |> expect(:ws_upgrade, fn _, _ ->
        send(self(), {:gun_error, pid, stream_ref, reason})
        stream_ref
      end)
      |> expect(:close, fn ^pid -> :ok end)

      assert Gun.connect(@conn) ==
               {:error,
                %SocketError{
                  cause: :critical_error,
                  details: %{reason: reason}
                }}
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
      |> expect(:close, fn ^pid -> :ok end)

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
      |> expect(:close, fn ^pid -> :ok end)

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
      |> expect(:close, fn ^pid -> :ok end)

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
      |> expect(:close, fn ^pid -> :ok end)

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
      |> expect(:close, fn ^pid -> :ok end)

      assert Gun.connect(@conn) ==
               {:error,
                %SocketError{
                  cause: :critical_error,
                  details: %{reason: "Something went wrong"}
                }}
    end
  end

  describe "disconnect/1" do
    test "success", %{pid: pid} do
      conn = %{@conn | pid: pid}

      expect(WSClientMock, :close, fn ^pid -> :ok end)

      assert Gun.disconnect(conn) == :ok
    end
  end

  describe "push_message/2" do
    test "subscribe", %{pid: pid, stream_ref: stream_ref} do
      conn = %{@conn | pid: pid, data: %{stream_ref: stream_ref}}
      msg = %Message{type: :subscribe, id: "__id__", payload: "__payload__"}
      text = Message.serialize(msg, Jason)

      expect(WSClientMock, :ws_send, fn ^pid, ^stream_ref, {:text, ^text} ->
        :ok
      end)

      assert Gun.push_message(conn, msg) == :ok
    end
  end

  describe "parse_message/2" do
    setup %{pid: pid, stream_ref: stream_ref} do
      {:ok, conn: %{@conn | pid: pid, data: %{stream_ref: stream_ref}}}
    end

    Enum.each(~w(complete next error), fn type ->
      test type, %{conn: conn, pid: pid, stream_ref: stream_ref} do
        assert Gun.parse_message(
                 conn,
                 {:gun_ws, pid, stream_ref,
                  {:text,
                   Jason.encode!(%{
                     "type" => unquote(type),
                     "id" => "__id__",
                     "payload" => "__payload__"
                   })}}
               ) ==
                 {:ok,
                  %Message{
                    type: String.to_existing_atom(unquote(type)),
                    id: "__id__",
                    payload: "__payload__"
                  }}
      end
    end)

    test "ignore invalid messages", %{
      conn: conn,
      pid: pid,
      stream_ref: stream_ref
    } do
      assert Gun.parse_message(
               conn,
               {:gun_ws, pid, stream_ref, {:text, "invalid"}}
             ) == :ignore

      assert Gun.parse_message(conn, "invalid") == :ignore
    end

    test "disconnect when gun down", %{conn: conn, pid: pid} do
      assert Gun.parse_message(
               conn,
               {:gun_down, pid, :ws, :normal, nil}
             ) == :disconnect
    end

    test "critical error", %{
      conn: conn,
      pid: pid,
      stream_ref: stream_ref
    } do
      reason = "Something went wrong"

      assert Gun.parse_message(conn, {:gun_error, pid, stream_ref, reason}) ==
               {:error,
                %SocketError{
                  cause: :critical_error,
                  details: %{reason: reason}
                }}
    end

    test "closed", %{
      conn: conn,
      pid: pid,
      stream_ref: stream_ref
    } do
      assert Gun.parse_message(conn, {:gun_ws, pid, stream_ref, :close}) ==
               {:error, %SocketError{cause: :closed}}
    end

    test "closed with payload", %{
      conn: conn,
      pid: pid,
      stream_ref: stream_ref
    } do
      payload = "__payload__"

      assert Gun.parse_message(
               conn,
               {:gun_ws, pid, stream_ref, {:close, payload}}
             ) ==
               {:error,
                %SocketError{cause: :closed, details: %{payload: payload}}}
    end

    test "closed with code and payload", %{
      conn: conn,
      pid: pid,
      stream_ref: stream_ref
    } do
      code = 1234
      payload = "__payload__"

      assert Gun.parse_message(
               conn,
               {:gun_ws, pid, stream_ref, {:close, code, payload}}
             ) ==
               {:error,
                %SocketError{
                  cause: :closed,
                  details: %{code: code, payload: payload}
                }}
    end
  end
end
