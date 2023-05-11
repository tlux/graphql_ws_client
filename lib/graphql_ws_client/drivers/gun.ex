defmodule GraphQLWSClient.Drivers.Gun do
  @moduledoc """
  A driver using the `:gun` library to connect to the GraphQL websocket.

  ## Usage

  The Gun driver is configured as default driver using Jason as default encoder
  and decoder. However, you still need to install the particular libraries
  yourself if you want to use them, so add these to your deps.

      {:gun, "~> 2.0"},
      {:jason, "~> 1.4"},

  ## Available Options

  See `GraphQLWSClient.Driver` to find out how to pass options to the driver.

  * `:ack_timeout` - The number of milliseconds to wait for a `connection_ack`
    after initiating the connection. Defaults to `5000`.

  * `:connect_options` - Connection options forwarded to `:gun.open/3`. See
    `t::gun.opts/0` for all available options.

  * `:json_library` - The library used to encode and decode JSON payloads.
    `Jason` by default.

  * `:upgrade_timeout` - The number of milliseconds to wait for a connection
    upgrade. Defaults to `5000`.
  """

  @behaviour GraphQLWSClient.Driver

  alias GraphQLWSClient.{Conn, Message, SocketError}
  alias GraphQLWSClient.Drivers.Gun.Opts

  @impl true
  def init(opts), do: Opts.new(opts)

  @impl true
  def connect(%Conn{config: config, opts: opts} = conn) do
    with {:start, :ok} <- {:start, ensure_adapter_ready(opts.adapter)},
         {:open, {:ok, pid}} <-
           {:open,
            opts.adapter.open(
              String.to_charlist(config.host),
              config.port,
              opts.connect_options
            )},
         {:ws, _, {:ok, stream_ref}} <-
           {:ws, pid, ws_connect(pid, config, opts)} do
      {:ok, %{conn | pid: pid, data: %{stream_ref: stream_ref}}}
    else
      {:start, error} ->
        error

      {:open, {:error, reason}} ->
        {:error, %SocketError{cause: :connect, details: %{reason: reason}}}

      {:ws, pid, error} ->
        opts.adapter.close(pid)
        error
    end
  end

  defp ensure_adapter_ready(:gun) do
    case Application.ensure_all_started(:gun) do
      {:ok, _} ->
        :ok

      {:error, {_app, reason}} ->
        {:error,
         %SocketError{cause: :critical_error, details: %{reason: reason}}}
    end
  end

  defp ensure_adapter_ready(_adapter), do: :ok

  defp ws_connect(pid, config, opts) do
    with {:await_up, {:ok, _protocol}} <-
           {:await_up,
            opts.adapter.await_up(pid, opts.connect_options.connect_timeout)},
         stream_ref = opts.adapter.ws_upgrade(pid, config.path),
         :ok <- await_upgrade(opts.upgrade_timeout),
         :ok <-
           init_connection(
             opts.adapter,
             pid,
             stream_ref,
             opts.json_library,
             config.init_payload
           ),
         :ok <- await_connection_ack(opts.json_library, opts.ack_timeout) do
      {:ok, stream_ref}
    else
      {:await_up, {:error, :timeout}} ->
        {:error, %SocketError{cause: :timeout}}

      {:await_up, {:error, {:down, _}}} ->
        {:error, %SocketError{cause: :closed}}

      error ->
        error
    end
  end

  @impl true
  def disconnect(%Conn{pid: pid, opts: %Opts{adapter: adapter}}) do
    adapter.close(pid)
  end

  defp await_upgrade(timeout) do
    receive do
      {:gun_upgrade, _pid, _stream_ref, ["websocket"], _headers} ->
        :ok

      {:gun_response, _pid, _stream_ref, _is_fin, status, _headers} ->
        {:error,
         %SocketError{cause: :unexpected_status, details: %{code: status}}}

      {:gun_error, _pid, _stream_ref, reason} ->
        {:error,
         %SocketError{cause: :critical_error, details: %{reason: reason}}}
    after
      timeout ->
        {:error, %SocketError{cause: :timeout}}
    end
  end

  defp init_connection(adapter, pid, stream_ref, json_library, init_payload) do
    push_message(adapter, pid, stream_ref, json_library, %Message{
      type: :connection_init,
      payload: init_payload
    })
  end

  defp await_connection_ack(json_library, timeout) do
    receive do
      {:gun_ws, _pid, _stream_ref, {:text, text}} ->
        case Message.parse(text, json_library) do
          {:ok, %Message{type: :connection_ack}} -> :ok
          _ -> {:error, %SocketError{cause: :unexpected_result}}
        end

      {type, _pid, _stream_ref, _msg} = msg
      when type in [:gun_error, :gun_ws] ->
        case parse_error(msg) do
          {:ok, error} -> {:error, error}
          :error -> {:error, %SocketError{cause: :unexpected_result}}
        end
    after
      timeout ->
        {:error, %SocketError{cause: :timeout}}
    end
  end

  @impl true
  def push_message(
        %Conn{opts: %Opts{} = opts} = conn,
        %Message{} = msg
      ) do
    push_message(
      opts.adapter,
      conn.pid,
      conn.data.stream_ref,
      opts.json_library,
      msg
    )
  end

  defp push_message(adapter, pid, stream_ref, json_library, %Message{} = msg) do
    adapter.ws_send(
      pid,
      stream_ref,
      {:text, Message.serialize(msg, json_library)}
    )
  end

  @impl true
  def parse_message(%Conn{}, {:gun_down, _, _, _, _}), do: :disconnect

  def parse_message(
        %Conn{opts: opts},
        {:gun_ws, _pid, _stream_ref, {:text, text}}
      ) do
    with :error <- Message.parse(text, opts.json_library) do
      :ignore
    end
  end

  def parse_message(%Conn{}, msg) do
    case parse_error(msg) do
      {:ok, error} -> {:error, error}
      :error -> :ignore
    end
  end

  defp parse_error({:gun_error, _pid, _stream_ref, reason}) do
    {:ok, %SocketError{cause: :critical_error, details: %{reason: reason}}}
  end

  defp parse_error({:gun_ws, _pid, _stream_ref, :close}) do
    {:ok, %SocketError{cause: :closed}}
  end

  defp parse_error({:gun_ws, _pid, _stream_ref, {:close, payload}}) do
    {:ok, %SocketError{cause: :closed, details: %{payload: payload}}}
  end

  defp parse_error({:gun_ws, _pid, _stream_ref, {:close, code, payload}}) do
    {:ok,
     %SocketError{cause: :closed, details: %{code: code, payload: payload}}}
  end

  defp parse_error(_), do: :error
end
