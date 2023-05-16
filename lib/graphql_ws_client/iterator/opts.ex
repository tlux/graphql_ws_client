defmodule GraphQLWSClient.Iterator.Opts do
  @moduledoc false

  @enforce_keys [:client, :query]

  defstruct [:client, :query, buffer_size: 1000, variables: %{}]

  @type t :: %__MODULE__{
          buffer_size: pos_integer() | :infinity,
          client: GraphQLWSClient.client(),
          query: GraphQLWSClient.query(),
          variables: GraphQLWSClient.variables()
        }

  @type valid :: t

  @spec new(Keyword.t()) :: t
  def new(opts), do: struct!(__MODULE__, opts)

  @spec validate!(t) :: valid | no_return
  def validate!(%__MODULE__{} = opts) do
    unless valid_buffer_size?(opts.buffer_size) do
      raise ArgumentError, "invalid buffer size"
    end

    opts
  end

  defp valid_buffer_size?(:infinity), do: true
  defp valid_buffer_size?(size) when is_integer(size) and size > 0, do: true
  defp valid_buffer_size?(_), do: false
end
