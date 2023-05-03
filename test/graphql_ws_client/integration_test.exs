defmodule GraphQLWSClient.IntegrationTest do
  use ExUnit.Case

  alias GraphQLWSClient.Event
  alias GraphQLWSClient.QueryError

  setup do
    client =
      start_supervised!(
        {GraphQLWSClient, url: "ws://localhost:8080/subscriptions"},
        id: :graphql_ws_client
      )

    {:ok, client: client}
  end

  describe "query" do
    @describetag :integration

    test "success", %{client: client} do
      assert {:ok, result} =
               GraphQLWSClient.query(client, """
                 query Posts {
                   posts {
                     id
                     author
                     body
                   }
                 }
               """)

      assert %{"data" => %{"posts" => _}} = result
    end

    test "error", %{client: client} do
      assert {:ok, %{"data" => nil, "errors" => errors}} =
               GraphQLWSClient.query(
                 client,
                 """
                   mutation CreatePost($author: String!, $body: String!) {
                     createPost(author: $author, body: $body) {
                       id
                       author
                       body
                     }
                   }
                 """,
                 %{"author" => "", "body" => "Lorem Ipsum"}
               )

      assert [%{"message" => "Author is blank"}] = errors
    end

    test "critical error", %{client: client} do
      assert {:error, %QueryError{errors: errors}} =
               GraphQLWSClient.query(
                 client,
                 """
                   mutation CreatePost($author: String!, $body: String!) {
                     createPost(author: $author, body: $body) {
                       foo
                     }
                   }
                 """,
                 %{"author" => "Author", "body" => "Lorem Ipsum"}
               )

      assert [%{"message" => message}] = errors
      assert message =~ "Cannot query field"
    end
  end

  describe "subscribe" do
    @describetag :integration

    test "success", %{client: client} do
      subscription_id =
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

      result =
        GraphQLWSClient.query!(
          client,
          """
            mutation CreatePost($author: String!, $body: String!) {
              createPost(author: $author, body: $body) {
                id
              }
            }
          """,
          %{"author" => "Tobi", "body" => "Lorem Ipsum"}
        )

      assert result["data"]["createPost"]

      assert_receive %Event{
        subscription_id: ^subscription_id,
        result: event_result,
        error: nil
      }

      assert event_result["data"]["postCreated"]["id"] ==
               result["data"]["createPost"]["id"]
    end

    test "error", %{client: client} do
      subscription_id =
        GraphQLWSClient.subscribe(
          client,
          """
            subscription PostCreated {
              postCreated {
                i
              }
            }
          """
        )

      assert_receive %Event{
        subscription_id: ^subscription_id,
        result: nil,
        error: %QueryError{errors: errors}
      }

      assert [%{"message" => message}] = errors
      assert message =~ "Cannot query field"
    end
  end

  describe "unsubscribe" do
    @describetag :integration

    test "success", %{client: client} do
      subscription_id =
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

      assert :ok = GraphQLWSClient.unsubscribe(client, subscription_id)

      result =
        GraphQLWSClient.query!(
          client,
          """
            mutation CreatePost($author: String!, $body: String!) {
              createPost(author: $author, body: $body) {
                id
              }
            }
          """,
          %{"author" => "Tobi", "body" => "Lorem Ipsum"}
        )

      assert result["data"]["createPost"]

      refute_receive %Event{}
    end
  end

  describe "stop" do
    @describetag :integration

    test "close handle", %{client: client} do
      assert Process.alive?(client)
      %{mod_state: %{pid: ws_pid}} = :sys.get_state(client)
      stop_supervised!(:graphql_ws_client)
      refute Process.alive?(client)
      refute Process.alive?(ws_pid)
    end
  end
end
