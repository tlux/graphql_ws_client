defmodule GraphQLWSClient.Drivers.Gun.Opts do
  @moduledoc false

  @default_connect_options %{
    connect_timeout: :timer.seconds(5),
    protocols: [:http]
  }

  defstruct ack_timeout: :timer.seconds(5),
            adapter: :gun,
            connect_options: @default_connect_options,
            json_library: Jason,
            upgrade_timeout: :timer.seconds(5)

  @type t :: %__MODULE__{
          ack_timeout: timeout,
          adapter: module,
          connect_options: %{optional(atom) => any},
          json_library: module,
          upgrade_timeout: timeout
        }

  @spec new(map) :: t
  def new(opts) do
    %{struct!(__MODULE__, opts) | connect_options: merge_connect_options(opts)}
  end

  defp merge_connect_options(opts) do
    connect_options =
      opts
      |> Map.get(:connect_options, %{})
      |> Map.new()

    Map.merge(@default_connect_options, connect_options)
  end
end
