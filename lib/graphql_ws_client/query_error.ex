defmodule GraphQLWSClient.QueryError do
  defexception errors: []

  @type t :: %__MODULE__{errors: [any]}

  def message(%__MODULE__{} = exception) do
    "Query error:\n\n" <> inspect(exception.errors, pretty: true)
  end
end
