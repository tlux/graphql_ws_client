defmodule GraphQLWSClient.GraphQLError do
  @moduledoc """
  Exception that contains errors from a GraphQL query.
  """

  defexception errors: []

  @type t :: %__MODULE__{errors: [any]}

  def message(%__MODULE__{} = exception) do
    "GraphQL errors:\n\n" <> inspect(exception.errors, pretty: true)
  end
end
