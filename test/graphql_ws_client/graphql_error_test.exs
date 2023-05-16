defmodule GraphQLWSClient.GraphQLErrorTest do
  use ExUnit.Case, async: true

  alias GraphQLWSClient.GraphQLError

  describe "Exception.message/1" do
    test "message" do
      errors = [
        %{
          "message" => "Something went wrong",
          "extensions" => %{"code" => 1234}
        },
        %{
          "message" => "Yet another error",
          "extensions" => %{"code" => 2345}
        }
      ]

      assert Exception.message(%GraphQLError{
               errors: [
                 %{
                   "message" => "Something went wrong",
                   "extensions" => %{"code" => 1234}
                 },
                 %{
                   "message" => "Yet another error",
                   "extensions" => %{"code" => 2345}
                 }
               ]
             }) ==
               "GraphQL errors:\n\n#{inspect(errors, pretty: true)}"
    end
  end
end
