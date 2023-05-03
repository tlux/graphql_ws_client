defmodule GraphQLWSClient.QueryError do
  defexception errors: []

  @type t :: %__MODULE__{errors: [any]}
end
