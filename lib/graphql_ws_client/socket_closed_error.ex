defmodule GraphQLWSClient.SocketClosedError do
  @moduledoc """
  Exception that indicates that the socket was closed.
  """

  defexception [:code, :payload]

  @type t :: %__MODULE__{code: nil | non_neg_integer, payload: String.t()}

  def message(%__MODULE__{}) do
    "GraphQL websocket closed"
  end
end
