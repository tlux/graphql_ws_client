defmodule GraphQLWSClient.State.Query do
  @moduledoc false

  @enforce_keys [:id, :from, :timeout_ref]

  defstruct [:id, :from, :timeout_ref]

  @type t :: %__MODULE__{
          from: GenServer.from(),
          id: term,
          timeout_ref: reference
        }
end
