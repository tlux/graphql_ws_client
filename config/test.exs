import Config

config :graphql_ws_client, TestGraphQLWSClient,
  url: "ws://localhost:8080/subscriptions",
  driver: {GraphQLWSClient.Drivers.Gun, connect_options: [connect_timeout: 500]}

config :logger, level: :debug
