defmodule GraphQLWSClient.Drivers.Gun.Opts do
  @moduledoc false

  defstruct adapter: :gun, json_library: Jason

  @type t :: %__MODULE__{adapter: module, json_library: module}

  @spec new(map) :: t
  def new(opts) do
    struct!(__MODULE__, opts)
  end
end
