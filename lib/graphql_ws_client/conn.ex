defmodule GraphQLWSClient.Conn do
  @moduledoc """
  A struct passed to the used driver that contains information about the current
  connection.
  """

  alias GraphQLWSClient.Config

  @enforce_keys [:config, :driver]

  defstruct [:config, :driver, :pid, opts: %{}, data: %{}]

  @type t :: %__MODULE__{
          config: Config.t(),
          data: %{optional(atom) => any},
          driver: module,
          opts: any,
          pid: nil | pid
        }
end
