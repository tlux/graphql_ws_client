defmodule GraphQLWSClient.State.Listener do
  @moduledoc false

  @enforce_keys [:pid]

  defstruct [:pid]

  @type t :: %__MODULE__{
          pid: pid
        }
end
