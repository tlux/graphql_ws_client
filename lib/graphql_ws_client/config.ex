defmodule GraphQLWSClient.Config do
  @moduledoc """
  A struct containing the configuration for a client.
  """

  @type t :: %__MODULE__{
          backoff_interval: non_neg_integer,
          connect_on_start: boolean,
          driver: module | {module, Keyword.t() | %{optional(atom) => any}},
          host: String.t(),
          init_payload: any,
          query_timeout: timeout,
          path: String.t(),
          port: :inet.port_number()
        }

  @enforce_keys [:host, :port]

  defstruct [
    :host,
    :init_payload,
    :port,
    backoff_interval: :timer.seconds(3),
    connect_on_start: true,
    driver: GraphQLWSClient.Drivers.Gun,
    query_timeout: :timer.seconds(5),
    path: "/"
  ]

  @protocols %{
    "http" => "ws",
    "https" => "wss",
    "ws" => "ws",
    "wss" => "wss"
  }

  @doc """
  Builds a new config.

  ## Options

  * `:backoff_interval` - The number of milliseconds to wait before trying to
    reconnect to the server.

  * `:connect_on_start` - Determines whether to immediately connect to the
    server as soon as the client is started. When set to `false`, you need to
    manually connect by calling `GraphQLWSClient.open/1`. Defaults to `true`.

  * `:driver` - The driver module to use. Defaults to
    `GraphQLWSClient.Drivers.Gun`. Can be either a module or a tuple in the form
    of `{MyDriverModule, opt_a: "hello world"}`. The options are passed to the
    driver's `init/1` callback, if defined.

  * `:host` - The host to connect to. This is ignored when `:url` is specified
    instead.

  * `:init_payload` - The payload send together with the `connection_init`
    message. Is useful when you need to authenticate a connection with a token,
    for instance.

  * `:path` - The path on the server. This is ignored when `:url` is specified
    instead. Defaults to `"/"`.

  * `:port` - The port to connect to. This is ignored when `:url` is specified
    instead.

  * `:url` - The URL of the websocket to connect to. Overwrites the `:host`,
    `:port` and `:path` options.
  """
  @spec new(opts :: t | Keyword.t() | map) :: t
  def new(%__MODULE__{} = config), do: config

  def new(opts) when is_map(opts) do
    opts |> Map.to_list() |> new()
  end

  def new(opts) when is_list(opts) do
    struct!(__MODULE__, expand_opts(opts))
  end

  defp expand_opts(opts) do
    case Keyword.pop(opts, :url) do
      {nil, opts} -> opts
      {url, opts} -> Keyword.merge(opts, url_to_opts(url))
    end
  end

  defp url_to_opts(url) do
    url
    |> parse_url!()
    |> Map.take([:host, :port, :path])
    |> Map.update!(:path, fn
      nil -> "/"
      path -> path
    end)
    |> Map.to_list()
  end

  defp parse_url!(url) do
    uri = URI.parse(url)

    if uri.scheme == nil || uri.scheme == "" do
      raise ArgumentError, "URL has no protocol"
    end

    if uri.host == nil || uri.host == "" do
      raise ArgumentError, "URL has empty host"
    end

    scheme =
      Map.get_lazy(@protocols, uri.scheme, fn ->
        raise ArgumentError,
              "URL has invalid protocol: #{uri.scheme} " <>
                "(allowed: #{Enum.join(Map.keys(@protocols), ", ")})"
      end)

    %{uri | scheme: scheme}
  end
end
