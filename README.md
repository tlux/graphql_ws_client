# GraphQL Websocket Client

[![Build](https://github.com/tlux/graphql_ws_client/actions/workflows/elixir.yml/badge.svg)](https://github.com/tlux/graphql_ws_client/actions/workflows/elixir.yml)
[![Coverage Status](https://coveralls.io/repos/github/tlux/graphql_ws_client/badge.svg?branch=main)](https://coveralls.io/github/tlux/graphql_ws_client?branch=main)
[![Module Version](https://img.shields.io/hexpm/v/graphql_ws_client.svg)](https://hex.pm/packages/graphql_ws_client)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/graphql_ws_client/)
[![License](https://img.shields.io/hexpm/l/graphql_ws_client.svg)](https://github.com/tlux/graphql_ws_client/blob/main/LICENSE.md)
[![Last Updated](https://img.shields.io/github/last-commit/tlux/graphql_ws_client.svg)](https://github.com/tlux/graphql_ws_client/commits/main)

An extensible client for connecting with GraphQL over Websockets following the
[graphql-ws](https://github.com/enisdenjo/graphql-ws) conventions.

## Installation

The package can be installed by adding `graphql_ws_client` to your list of
dependencies in `mix.exs`.

```elixir
def deps do
  [
    {:graphql_ws_client, "~> 1.0"},
  ]
end
```

If you are using the default configuration, `GraphQLWSClient.Drivers.Gun` is
used as driver and you will need the `gun` and `jason` packages as well.

```elixir
def deps do
  [
    # ...
    {:gun, "~> 2.0"},
    {:jason, "~> 1.4"},
  ]
end
```

Take a
look in the driver documentation to find out how to customize driver options.

Alternatively, you can write your own driver based on the
`GraphQLWSClient.Driver` behaviour.

## Usage

```elixir
{:ok, socket} = GraphQLWSClient.start_link(url: "ws://localhost:4000/socket")

{:ok, subscription_id} = GraphQLWSClient.subscribe(
  socket,
  "subscription PostCreated { ... }"
)

{:ok, _} = GraphQLWSClient.query(socket, "mutation CreatePost { ... }")

receive do
  %GraphQLWSClient.Event{} = event ->
    IO.inspect(event)
end

GraphQLClient.close(socket)
```

## Custom Client

If you want to run the client as part of a supervision tree in your
application, you can also `use GraphQLWSClient` to create your own client.

```elixir
defmodule MyClient do
  use GraphQLWSClient, otp_app: :my_app
end
```

Then, you can configure your client using a config file:

```elixir
import Config

config :my_app, MyClient,
  url: "ws://localhost:4000/socket"
```

## Docs

Documentation can be found at <https://hexdocs.pm/graphql_ws_client> or
generated locally using `mix docs`.
