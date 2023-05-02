defmodule GraphQLWSClient.SocketClosedError do
  defexception [:code, :payload]

  @type t :: %__MODULE__{code: nil | non_neg_integer, payload: String.t()}

  def message(%__MODULE__{} = exception) do
    "Socket closed (code #{exception.code})"
  end
end
