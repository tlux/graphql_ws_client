defmodule GraphQLWSClient.GraphQLErrorTest do
  use ExUnit.Case, async: true

  alias GraphQLWSClient.GraphQLError

  describe "Exception.message/1" do
    test "message" do
      assert Exception.message(%GraphQLError{
               errors: [
                 %{
                   "message" => "Something went wrong",
                   "extensions" => %{"code" => 1234}
                 },
                 %{
                   "message" => "Yet another error",
                   "extensions" => %{"code" => 2345}
                 },
                 %{
                   "foo" => "bar"
                 }
               ]
             }) ==
               Enum.join(
                 [
                   "GraphQL error:",
                   "- Something went wrong",
                   "- Yet another error",
                   "- #{inspect(%{"foo" => "bar"})}"
                 ],
                 "\n"
               )
    end
  end
end
