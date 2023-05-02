defmodule GraphQLWSClientTest do
  use ExUnit.Case

  doctest GraphQLWSClient

  test "greets the world" do
    assert GraphQLWSClient.hello() == :world
  end
end
