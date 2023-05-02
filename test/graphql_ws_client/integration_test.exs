defmodule GraphQLWSClient.IntegrationTest do
  use ExUnit.Case

  @tag :integration
  test "query" do
    client =
      start_supervised!(
        {GraphQLWSClient, url: "ws://localhost:4000/subscriptions"}
      )

    {:ok, result} =
      GraphQLWSClient.query(client, """
        query Posts {
          posts(first: 10) {
            edges {
              node {
                id
                author
                body
              }
            }
          }
        }
      """)

    {:ok, result2} =
      GraphQLWSClient.query(client, """
        query Posts {
          posts(first: 10) {
            foo
          }
        }
      """)

    # TODO

    IO.inspect(result)
    IO.inspect(result2)
  end
end
