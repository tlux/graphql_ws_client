defmodule GraphQLWSClient.Options do
  @moduledoc false

  @type t :: %__MODULE__{
          host: String.t(),
          port: non_neg_integer,
          path: String.t(),
          backoff_interval: non_neg_integer,
          init_payload: any,
          init_timeout: timeout,
          connect_timeout: timeout,
          upgrade_timeout: timeout
        }

  @enforce_keys [:host, :port]

  defstruct [
    :host,
    :port,
    {:path, "/"},
    :init_payload,
    {:backoff_interval, 3000},
    {:connect_timeout, 5000},
    {:upgrade_timeout, 5000},
    {:init_timeout, 5000}
  ]

  @spec new(Keyword.t() | map) :: t
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
      raise ArgumentError, "URL is missing host"
    end

    if uri.port == nil do
      raise ArgumentError, "URL is missing port"
    end

    uri
  end
end
