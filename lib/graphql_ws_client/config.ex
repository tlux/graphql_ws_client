defmodule GraphQLWSClient.Config do
  @moduledoc false

  @type t :: %__MODULE__{
          backoff_interval: non_neg_integer,
          connect_on_start: boolean,
          connect_timeout: timeout,
          driver: module | {module, Keyword.t()},
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
    driver: {GraphQLWSClient.Drivers.Websocket, adapter: :gun},
    init_timeout: 5000,
    json_library: Jason,
    path: "/",
    upgrade_timeout: 5000
  ]

  @spec new(t | Keyword.t() | map) :: t
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
