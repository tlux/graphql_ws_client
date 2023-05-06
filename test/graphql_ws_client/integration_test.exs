defmodule GraphQLWSClient.IntegrationTest do
  use ExUnit.Case

  alias GraphQLWSClient.{Event, QueryError}

  setup do
    client = start_supervised!(TestGraphQLWSClient, id: :graphql_ws_client)
    {:ok, client: client}
  end

  describe "query" do
    @describetag :integration

    test "success" do
      assert {:ok, result} =
               TestGraphQLWSClient.query("""
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

    test "error" do
      assert {:ok, %{"data" => nil, "errors" => errors}} =
               TestGraphQLWSClient.query(
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

    test "critical error" do
      assert {:error, %QueryError{errors: errors}} =
               TestGraphQLWSClient.query(
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

    test "success" do
      {:ok, subscription_id} =
        TestGraphQLWSClient.subscribe("""
          subscription PostCreated {
            postCreated {
              id
            }
          }
        """)

      result =
        TestGraphQLWSClient.query!(
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

    test "error" do
      {:ok, subscription_id} =
        TestGraphQLWSClient.subscribe("""
          subscription PostCreated {
            postCreated {
              i
            }
          }
        """)

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

    test "success" do
      {:ok, subscription_id} =
        TestGraphQLWSClient.subscribe("""
          subscription PostCreated {
            postCreated {
              id
            }
          }
        """)

      assert :ok = TestGraphQLWSClient.unsubscribe(subscription_id)

      result =
        TestGraphQLWSClient.query!(
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
      %{mod_state: %{conn: %{pid: pid}}} = :sys.get_state(client)

      stop_supervised!(:graphql_ws_client)

      refute Process.alive?(client)
      refute Process.alive?(pid)
    end
  end
end
