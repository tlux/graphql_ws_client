defmodule GraphQLWSClient.IntegrationTest do
  use ExUnit.Case

  alias GraphQLWSClient.Message

  setup do
    client =
      start_supervised!(
        {GraphQLWSClient,
         url: "ws://localhost:4000/subscriptions", init_payload: %{}}
      )

    {:ok, client: client}
  end

  @tag :integration
  test "query", %{client: client} do
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

  @tag :integration
  test "subscription", %{client: client} do
    # should fail when not authenticated!
    {:ok, subscription_id} =
      GraphQLWSClient.subscribe(
        client,
        """
          subscription PostCreated {
            postCreated {
              id
            }
          }
        """
      )

    {:ok, result} =
      GraphQLWSClient.query(
        client,
        """
          mutation CreatePost($input: CreatePostInput!) {
            createPost(input: $input) {
              successful
              result {
                id
              }
            }
          }
        """,
        %{"input" => %{"author" => "Tobi", body: "Lorem Ipsum"}}
      )

    assert result["data"]["createPost"]["successful"] == true

    assert_receive %Message{subscription_id: ^subscription_id, payload: payload}

    assert payload["data"]["postCreated"]["id"] ==
             result["data"]["createPost"]["result"]["id"]
  end
end
