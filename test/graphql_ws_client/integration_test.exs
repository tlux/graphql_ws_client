defmodule GraphQLWSClient.IntegrationTest do
  use ExUnit.Case

  alias GraphQLWSClient.{Event, GraphQLError, TestClient}

  @moduletag :integration

  setup do
    {:ok, client: start_supervised!(TestClient, id: :test_client)}
  end

  describe "query" do
    test "success" do
      assert {:ok, result} =
               GraphQLWSClient.query(TestClient, """
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
               GraphQLWSClient.query(
                 TestClient,
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
      assert {:error, %GraphQLError{errors: errors}} =
               GraphQLWSClient.query(
                 TestClient,
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
    test "success" do
      {:ok, subscription_id} =
        GraphQLWSClient.subscribe(TestClient, """
          subscription PostCreated {
            postCreated {
              id
            }
          }
        """)

      result =
        GraphQLWSClient.query!(
          TestClient,
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
        type: :next,
        subscription_id: ^subscription_id,
        payload: event_result
      }

      assert event_result["data"]["postCreated"]["id"] ==
               result["data"]["createPost"]["id"]
    end

    test "error" do
      {:ok, subscription_id} =
        GraphQLWSClient.subscribe(TestClient, """
          subscription PostCreated {
            postCreated {
              i
            }
          }
        """)

      assert_receive %Event{
        type: :error,
        subscription_id: ^subscription_id,
        payload: %GraphQLError{errors: errors}
      }

      assert [%{"message" => message}] = errors
      assert message =~ "Cannot query field"
    end
  end

  describe "unsubscribe" do
    test "success" do
      {:ok, subscription_id} =
        GraphQLWSClient.subscribe(TestClient, """
          subscription PostCreated {
            postCreated {
              id
            }
          }
        """)

      assert :ok = GraphQLWSClient.unsubscribe(TestClient, subscription_id)

      result =
        GraphQLWSClient.query!(
          TestClient,
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
    test "close handle", %{client: client} do
      assert Process.alive?(client)
      %{mod_state: %{conn: %{pid: pid}}} = :sys.get_state(client)

      stop_supervised!(:test_client)

      refute Process.alive?(client)
      refute Process.alive?(pid)
    end
  end

  describe "stream" do
    test "success" do
      test_pid = self()

      stream =
        TestClient
        |> GraphQLWSClient.stream!("""
          subscription PostCreated {
            postCreated {
              author
              body
            }
          }
        """)
        |> Stream.map(& &1["data"]["postCreated"])
        |> Stream.each(fn data ->
          send(test_pid, {:event, data})
        end)
        |> Stream.take(2)

      task = Task.async(fn -> Enum.to_list(stream) end)

      payloads = [
        %{"author" => "Tobi", "body" => "Lorem Ipsum"},
        %{"author" => "Casper", "body" => "Dolor sit amet"}
      ]

      refute_receive {:event, _}

      Enum.each(payloads, fn payload ->
        GraphQLWSClient.query!(
          TestClient,
          """
            mutation CreatePost($author: String!, $body: String!) {
              createPost(author: $author, body: $body) {
                id
              }
            }
          """,
          payload
        )

        assert_receive {:event, ^payload}
      end)

      assert Task.await(task) == payloads
    end
  end
end
