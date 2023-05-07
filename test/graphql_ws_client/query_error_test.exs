defmodule GraphQLWSClient.QueryErrorTest do
  use ExUnit.Case, async: true

  alias GraphQLWSClient.QueryError

  describe "Exception.message/1" do
    test "message" do
      assert Exception.message(%QueryError{
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
               "GraphQL query error:\n\n" <>
                 "[\n" <>
                 "  %{\"extensions\" => %{\"code\" => 1234}, \"message\" => \"Something went wrong\"},\n" <>
                 "  %{\"extensions\" => %{\"code\" => 2345}, \"message\" => \"Yet another error\"}\n]"
    end
  end
end
