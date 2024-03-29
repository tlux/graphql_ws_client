{:ok, socket} =
  GraphQLWSClient.start_link(url: "ws://localhost:8080/subscriptions")

Task.start_link(fn ->
  socket
  |> GraphQLWSClient.stream!("""
    subscription PostCreated {
      postCreated {
        id
        author
        body
      }
    }
  """)
  |> Stream.each(&IO.inspect/1)
  |> Stream.run()
end)

defmodule QueryLoop do
  def query(socket) do
    Process.sleep(2000)

    GraphQLWSClient.query(
      socket,
      """
        mutation CreatePost($author: String!, $body: String!) {
          createPost(author: $author, body: $body) {
            id
          }
        }
      """,
      %{"author" => "Tobi", "body" => "Lorem Ipsum"}
    )

    query(socket)
  end
end

QueryLoop.query(socket)
Process.sleep(15000)
