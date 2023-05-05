defmodule GraphQLWSClient.Drivers.Websocket.Conn do
  defstruct [:pid, :stream_ref]

  @type t :: %__MODULE__{pid: pid, stream_ref: reference}
end
