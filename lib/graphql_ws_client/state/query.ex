defmodule GraphQLWSClient.State.Query do
  @moduledoc false

  @enforce_keys [:id, :from, :timeout_ref]

  defstruct [:id, :from, :timeout_ref]

  @type t :: %__MODULE__{
          id: term,
          from: GenServer.from(),
          timeout_ref: reference
        }
end
