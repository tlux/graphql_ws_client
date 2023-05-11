defmodule GraphQLWSClient.State.Query do
  @moduledoc false

  @enforce_keys [:from, :timeout_ref]

  defstruct [:from, :timeout_ref]

  @type t :: %__MODULE__{
          from: GenServer.from(),
          timeout_ref: reference
        }
end
