defmodule GraphQLWSClient.IntegrationTest do
  use ExUnit.Case

  alias GraphQLWSClient.Event
  alias GraphQLWSClient.QueryError

  setup do
    client =
      start_supervised!(
        {GraphQLWSClient,
         url: "ws://localhost:4000/subscriptions",
         init_payload: %{
           "token" =>
             "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJ0ZW1wbGVyX2NsYW4iLCJleHAiOjE2ODM2NzE5MjAsImlhdCI6MTY4MzA2NzEyMCwiaXNzIjoidGVtcGxlcl9jbGFuIiwianRpIjoiNzg5MWNjOTEtMzQyYS00MWFmLWJjOWYtZDgwYjE0ODFmZDIyIiwibmJmIjoxNjgzMDY3MTE5LCJzdWIiOiI4NDg3ZDcyOS1lMGM3LTQxZGUtYmIxOC00MjZkNWM4OGIyODUiLCJ0eXAiOiJhY2Nlc3MifQ.EnyNWvmLS0i-haCWSJSbICpejo5kqVBixAInXoIV9uNBKV0APqhHagrcF4E8iYKb0MhGcLOA5HzZtEq-J8S8Mw"
         }},
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

      assert %{"data" => %{"posts" => %{"edges" => _}}} = result
    end

    test "error", %{client: client} do
      assert {:error, %QueryError{errors: errors}} =
               GraphQLWSClient.query(client, """
                 query Posts {
                   posts(first: 10) {
                     foo
                   }
                 }
               """)

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

      assert_receive %Event{
        subscription_id: ^subscription_id,
        data: event_result,
        error: nil
      }

      assert event_result["data"]["postCreated"]["id"] ==
               result["data"]["createPost"]["result"]["id"]
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
        data: nil,
        error: %QueryError{errors: errors}
      }

      assert [%{"message" => message}] = errors
      assert message =~ "Cannot query field"
    end
  end

  describe "unsubscribe" do
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
            mutation CreatePost($input: CreatePostInput!) {
              createPost(input: $input) {
                successful
              }
            }
          """,
          %{"input" => %{"author" => "Tobi", body: "Lorem Ipsum"}}
        )

      assert result["data"]["createPost"]["successful"] == true

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
