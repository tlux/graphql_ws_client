# GraphQL Websocket Client

A client for connecting to GraphQL websockets that are implemented following the
[graphql-ws](https://github.com/enisdenjo/graphql-ws) conventions.

## Installation

The package can be installed by adding `graphql_ws_client` to your list of
dependencies in `mix.exs`. If you are using the default configuration, you will
also need the `jason` and `gun` packages.

```elixir
def deps do
  [
    {:graphql_ws_client, "~> 0.1.0"},
    {:gun, "~> 2.0"},
    {:jason, "~> 1.4"},
  ]
end
```

## Docs

Documentation can be found at <https://hexdocs.pm/graphql_ws_client> or
generated locally using `mix docs`.

