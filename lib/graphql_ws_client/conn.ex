defmodule GraphQLWSClient.Conn do
  @moduledoc false

  alias GraphQLWSClient.Config

  @enforce_keys [:config, :driver]

  defstruct [:config, :driver, :pid, opts: %{}, data: %{}]

  @type t :: %__MODULE__{
          config: Config.t(),
          data: %{optional(atom) => any},
          driver: module,
          opts: %{optional(atom) => any},
          pid: nil | pid
        }
end
