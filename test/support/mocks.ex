Mox.defmock(GraphQLWSClient.Drivers.Mock, for: GraphQLWSClient.Driver)

Mox.defmock(GraphQLWSClient.Drivers.MockWithoutInit,
  for: GraphQLWSClient.Driver,
  skip_optional_callbacks: true
)

Mox.defmock(GraphQLWSClient.WSClientMock, for: GraphQLWSClient.WSClient)
