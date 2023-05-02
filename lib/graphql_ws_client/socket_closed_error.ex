defmodule GraphQLWSClient.SocketClosedError do
  defexception [:code, :payload]

  def message(%__MODULE__{} = exception) do
    "Socket closed (code #{exception.code})"
  end
end
