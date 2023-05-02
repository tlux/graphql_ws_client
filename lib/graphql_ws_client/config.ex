defmodule GraphQLWSClient.Config do
  @moduledoc false

  @spec json_library() :: module
  def json_library do
    Application.get_env(:graphql_ws_client, :json_library, Jason)
  end
end
