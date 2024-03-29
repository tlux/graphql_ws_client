{:ok, socket} =
  GraphQLWSClient.start_link(url: "ws://localhost:8080/subscriptions")

socket
|> GraphQLWSClient.query!("""
  query GetPosts {
    posts {
      id
      body
      author
    }
  }
""")
|> IO.inspect()
