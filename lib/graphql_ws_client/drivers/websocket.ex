defmodule GraphQLWSClient.Drivers.Websocket do
  @moduledoc false

  @behaviour GraphQLWSClient.Driver

  alias GraphQLWSClient.{Config, Conn, Message, SocketError}

  @impl true
  def connect(%Config{} = config) do
    with {:open, {:ok, pid}} <-
           {:open,
            :gun.open(
              String.to_charlist(config.host),
              config.port,
              %{protocols: [:http]}
            )},
         {:await_up, {:ok, _protocol}} <-
           {:await_up, :gun.await_up(pid, config.connect_timeout)},
         stream_ref = :gun.ws_upgrade(pid, config.path),
         :ok <- await_upgrade(config.upgrade_timeout),
         :ok <- init_connection(pid, stream_ref, config),
         :ok <- await_connection_ack(config) do
      {:ok,
       %Conn{
         json_library: config.json_library,
         pid: pid,
         stream_ref: stream_ref
       }}
    else
      {:open, _} ->
        {:error, %SocketError{cause: :connect}}

      {:await_up, {:error, :timeout}} ->
        {:error, %SocketError{cause: :timeout}}

      {:await_up, {:error, {:down, _}}} ->
        {:error, %SocketError{cause: :closed}}

      error ->
        error
    end
  end

  @impl true
  def disconnect(%Conn{pid: pid}) do
    :gun.close(pid)
  end

  defp await_upgrade(timeout) do
    receive do
      {:gun_upgrade, _pid, _stream_ref, ["websocket"], _headers} ->
        :ok

      {:gun_response, _pid, _stream_ref, _is_fin, status, _headers} ->
        {:error, %SocketError{cause: :result, details: %{status: status}}}

      {:gun_error, _pid, _stream_ref, reason} ->
        {:error, %SocketError{cause: :result, details: %{reason: reason}}}
    after
      timeout ->
        {:error, %SocketError{cause: :timeout}}
    end
  end

  defp init_connection(pid, stream_ref, %Config{} = config) do
    push_message(pid, stream_ref, config.json_library, %{
      type: "connection_init",
      payload: config.init_payload
    })
  end

  defp await_connection_ack(%Config{} = config) do
    receive do
      {:gun_error, _pid, _stream_ref, reason} ->
        {:error, %SocketError{cause: :result, details: %{reason: reason}}}

      {:gun_ws, _pid, _stream_ref, {:text, msg}} ->
        case config.json_library.decode!(msg) do
          %{"type" => "connection_ack"} -> :ok
          _ -> {:error, %SocketError{cause: :result}}
        end

      {:gun_ws, _pid, _stream_ref, _msg} ->
        {:error, %SocketError{cause: :result}}
    after
      config.init_timeout ->
        {:error, %SocketError{cause: :timeout}}
    end
  end

  @impl true
  def push_message(%Conn{} = conn, msg) do
    push_message(conn.pid, conn.stream_ref, conn.json_library, msg)
  end

  defp push_message(pid, stream_ref, json_library, msg) do
    :gun.ws_send(pid, stream_ref, {:text, json_library.encode!(msg)})
  end

  @impl true
  def handle_message(_conn, {:gun_error, _pid, _stream_ref, reason}) do
    {:error, %SocketError{cause: :result, details: %{reason: reason}}}
  end

  def handle_message(conn, {:gun_ws, _pid, _stream_ref, {:text, text}}) do
    case conn.json_library.decode(text) do
      {:ok, %{"type" => "complete", "id" => id}} ->
        {:ok, %Message{type: :complete, id: id}}

      {:ok, %{"type" => "next", "id" => id, "payload" => payload}} ->
        {:ok, %Message{type: :next, id: id, payload: payload}}

      {:ok, %{"type" => "error", "id" => id, "payload" => payload}} ->
        {:ok, %Message{type: :error, id: id, payload: payload}}

      _ ->
        :ignore
    end
  end

  def handle_message(_conn, {:gun_ws, _pid, _stream_ref, :close}) do
    {:error, %SocketError{cause: :closed}}
  end

  def handle_message(_conn, {:gun_ws, _pid, _stream_ref, {:close, payload}}) do
    {:error, %SocketError{cause: :closed, details: %{payload: payload}}}
  end

  def handle_message(
        _conn,
        {:gun_ws, _pid, _stream_ref, {:close, code, payload}}
      ) do
    {:error,
     %SocketError{cause: :closed, details: %{code: code, payload: payload}}}
  end

  def handle_message(_conn, _msg), do: :ignore
end
