defmodule GraphQLWSClient.MixProject do
  use Mix.Project

  @github_url "https://github.com/tlux/graphql_ws_client"
  @version "0.1.2"

  def project do
    [
      app: :graphql_ws_client,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.post": :test,
        coveralls: :test,
        credo: :test,
        dialyzer: :test,
        test: :test
      ],
      dialyzer: dialyzer(),

      # Docs
      name: "GraphQL-over-Websocket Client",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:connection, "~> 1.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.16", only: :test, runtime: false},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false},
      {:gun, "~> 2.0", optional: true},
      {:jason, "~> 1.4", optional: true},
      {:mix_audit, "~> 2.1", only: [:dev, :test]},
      {:mox, "~> 1.0", only: :test},
      {:uuid, "~> 1.1"}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:ex_unit],
      plt_add_deps: :app_tree,
      plt_file: {:no_warn, "priv/plts/graphql_ws_client.plt"}
    ]
  end

  def package do
    [
      description:
        "A client for connecting with GraphQL over Websockets following the " <>
          "graphql-ws conventions.",
      exclude_patterns: [~r/\Apriv\/plts/],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @github_url
      }
    ]
  end

  defp docs do
    [
      extras: [
        "LICENSE.md": [title: "License"],
        "README.md": [title: "Readme"]
      ],
      main: "readme",
      source_url: @github_url,
      source_ref: "v#{@version}",
      groups_for_modules: [
        Driver: [
          GraphQLWSClient.Conn,
          GraphQLWSClient.Driver,
          GraphQLWSClient.Message
        ],
        "Included Drivers": [
          GraphQLWSClient.Drivers.Gun
        ]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
