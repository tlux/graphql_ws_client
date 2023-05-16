defmodule GraphQLWSClient.GraphQLError do
  @moduledoc """
  Exception that contains errors from a GraphQL query.
  """

  defexception errors: []

  @type t :: %__MODULE__{errors: [any]}

  def message(%__MODULE__{} = exception) do
    errors = Enum.map_join(exception.errors, "\n", &map_error/1)
    "GraphQL error:\n#{errors}"
  end

  defp map_error(%{"message" => message}) do
    "- #{message}"
  end

  defp map_error(error), do: "- #{inspect(error)}"
end
