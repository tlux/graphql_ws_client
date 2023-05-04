defmodule GraphQLWSClient.SocketError do
  @moduledoc """
  Exception that indicates a socket error.
  """

  defexception [:code, :payload]

  @type t :: %__MODULE__{code: nil | non_neg_integer, payload: String.t()}

  def message(_) do
    "GraphQL websocket error"
  end
end
