defmodule GraphQLWSClient.OperationError do
  @moduledoc """
  An error that indicates an invalid operation.
  """

  defexception [:message]
end
