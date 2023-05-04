defmodule GraphQLWSClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :graphql_ws_client,
      version: "0.1.0",
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
      dialyzer: dialyzer()
    ]
  end

  def package do
    [
      description:
        "A client for connecting with Websockets following the " <>
          "graphql-ws conventions.",
      licenses: ["MIT"],
      links: %{}
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:crypto, :logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:connection, "~> 1.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.16", only: :test},
      {:gun, "~> 2.0"},
      {:jason, "~> 1.4", optional: true},
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
