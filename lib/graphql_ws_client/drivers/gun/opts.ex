defmodule GraphQLWSClient.Drivers.Gun.Opts do
  @moduledoc false

  @default_connect_options %{
    connect_timeout: 5000,
    protocols: [:http]
  }

  defstruct ack_timeout: 5000,
            adapter: :gun,
            connect_options: @default_connect_options,
            json_library: Jason,
            upgrade_timeout: 5000

  @type t :: %__MODULE__{
          ack_timeout: timeout,
          adapter: module,
          connect_options: %{optional(atom) => any},
          json_library: module,
          upgrade_timeout: timeout
        }

  @type foo :: :gun.opts()

  @spec new(map) :: t
  def new(opts) do
    %{struct!(__MODULE__, opts) | connect_options: merge_connect_options(opts)}
  end

  defp merge_connect_options(opts) do
    Map.merge(
      @default_connect_options,
      opts
      |> Map.get(:connect_options, %{})
      |> Map.new()
    )
  end
end
