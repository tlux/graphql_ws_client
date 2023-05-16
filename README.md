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

Connect to a socket:

```elixir
{:ok, socket} = GraphQLWSClient.start_link(url: "ws://localhost:4000/socket")
```

Send a query or mutation and return the result immediately:

```elixir
{:ok, result} = GraphQLWSClient.query(socket, "query GetPost { ... }")
```

Register a subscription to listen for events:

```elixir
{:ok, subscription_id} = GraphQLWSClient.subscribe(
  socket,
  "subscription PostCreated { ... }"
)

GraphQLWSClient.query!(socket, "mutation CreatePost { ... }")

receive do
  %GraphQLWSClient.Event{type: :error, id: ^subscription_id, payload: error} ->
    IO.inspect(error, label: "error")
  %GraphQLWSClient.Event{type: :next, id: ^subscription_id, payload: result} ->
    IO.inspect(result)
  %GraphQLWSClient.Event{type: :complete, id: ^subscription_id} ->
    IO.puts("Stream closed")
end

GraphQLClient.close(socket)
```

You would usually put this inside of a custom `GenServer` and handle the events
in `handle_info/3`.

Alternatively, you can create a stream of results:

```elixir
socket
|> GraphQLWSClient.stream!("subscription PostCreated { ... }")
|> Stream.each(fn result ->
  IO.inspect(result)
end)
|> Stream.run()
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
