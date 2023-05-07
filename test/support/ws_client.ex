defmodule GraphQLWSClient.WSClient do
  @moduledoc false

  @callback open(
              :inet.hostname() | :inet.ip_address(),
              :inet.port_number(),
              map
            ) :: {:ok, pid} | {:error, any}

  @callback await_up(pid, timeout) ::
              {:ok, :http | :http2 | :raw | :socks} | {:error, any}

  @callback ws_upgrade(pid, binary) :: reference

  @callback ws_send(pid, reference, frame :: term) :: :ok

  @callback close(pid) :: :ok
end
