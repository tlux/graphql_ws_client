defmodule GraphQLWSClient.WSClient do
  @moduledoc false

  @callback open(
              charlist,
              :inet.hostname() | :inet.ip_address(),
              :inet.port_number()
            ) :: {:ok, pid} | {:error, any}

  @callback await_up(pid, timeout) ::
              {:ok, :http | :http2 | :raw | :socks} | {:error, any}

  @callback ws_upgrade(pid, binary) :: reference

  @callback ws_send(pid, reference, :gun.ws_frame() | [:gun.ws_frame()]) :: :ok

  @callback close(pid) :: :ok
end
