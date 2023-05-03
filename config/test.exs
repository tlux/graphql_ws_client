import Config

config :graphql_ws_client, TestGraphQLWSClient,
  url: "ws://localhost:8080/subscriptions",
  connect_timeout: 500
