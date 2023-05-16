defmodule GraphQLWSClient.FormatLog do
  @moduledoc false

  @spec format_log(String.Chars.t() | Exception.t()) :: String.t()
  def format_log(exception) when is_exception(exception) do
    exception
    |> Exception.message()
    |> format_log()
  end

  def format_log(text) do
    "graphql_ws_client: #{text}"
  end
end
