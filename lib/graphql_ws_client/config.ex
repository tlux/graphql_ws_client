defmodule GraphQLWSClient.Config do
  @moduledoc """
  A struct containing the configuration for a client.
  """

  @type t :: %__MODULE__{
          backoff_interval: non_neg_integer,
          connect_on_start: boolean,
          connect_timeout: timeout,
          driver: module | {module, Keyword.t() | %{optional(atom) => any}},
          host: String.t(),
          init_payload: any,
          init_timeout: timeout,
          json_library: module,
          path: String.t(),
          port: :inet.port_number(),
          upgrade_timeout: timeout
        }

  @enforce_keys [:host, :port]

  defstruct [
    :host,
    :init_payload,
    :port,
    backoff_interval: 3000,
    connect_on_start: true,
    connect_timeout: 5000,
    driver: GraphQLWSClient.Drivers.Gun,
    init_timeout: 5000,
    json_library: Jason,
    path: "/",
    upgrade_timeout: 5000
  ]

  @doc """
  Builds a new config.

  ## Options

  * `:backoff_interval` - The number of milliseconds to wait before trying to
    reconnect to the server.

  * `:connect_on_start` - Determines whether to immediately connect to the
    server as soon as the client is started. When set to `false`, you need to
    manually connect by calling `GraphQLWSClient.open/1`. Defaults to `true`.

  * `:connect_timeout` - The connection timeout. Defaults to `5000`.

  * `:driver` - The driver module to use. Defaults to
    `GraphQLWSClient.Drivers.Gun`.

  * `:host` - The host to connect to. This is ignored when `:url` is specified
    instead.

  * `:init_payload` - The payload send together with the `connection_init`
    message. Is useful when you need to authenticate a connection with a token,
    for instance.

  * `:init_timeout` - The number of milliseconds to wait for a `connection_ack`
    after initiating the connection. Defaults to `5000`.

  * `:json_library` - The JSON decoder/encoder to use. Defaults to `Jason`.

  * `:path` - The path on the server. This is ignored when `:url` is specified
    instead. Defaults to `"/"`.

  * `:port` - The port to connect to. This is ignored when `:url` is specified
    instead.

  * `:upgrade_timeout` - The number of milliseconds to wait for a connection
    upgrade. Defaults to `5000`.

  * `:url` - The URL of the websocket to connect to. Overwrites the `:host`,
    `:port` and `:path` options.
  """
  @spec new(opts :: t | Keyword.t() | map) :: t
  def new(%__MODULE__{} = config), do: config

  def new(opts) when is_map(opts) do
    opts |> Map.to_list() |> new()
  end

  def new(opts) when is_list(opts) do
    opts =
      case Keyword.pop(opts, :url) do
        {nil, opts} ->
          opts

        {url, opts} ->
          url_opts =
            url
            |> parse_url!()
            |> Map.take([:host, :port, :path])
            |> Map.update!(:path, fn
              nil -> "/"
              path -> path
            end)
            |> Map.to_list()

          Keyword.merge(opts, url_opts)
      end

    struct!(__MODULE__, opts)
  end

  defp parse_url!(url) do
    uri = URI.parse(url)

    if uri.scheme == nil || uri.scheme == "" do
      raise ArgumentError, "URL has no protocol"
    end

    allowed_protocols = ~w(ws wss)

    if uri.scheme not in allowed_protocols do
      raise ArgumentError,
            "URL has invalid protocol: #{uri.scheme} " <>
              "(allowed: #{Enum.join(allowed_protocols, ", ")})"
    end

    if uri.host == nil || uri.host == "" do
      raise ArgumentError, "URL has empty host"
    end

    uri
  end
end
