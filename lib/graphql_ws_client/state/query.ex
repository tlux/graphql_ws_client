defmodule GraphQLWSClient.State.Query do
  @moduledoc false

  @enforce_keys [:id, :from, :payload, :timeout_ref]

  defstruct [:id, :from, :payload, :timeout_ref]

  @type t :: %__MODULE__{
          id: term,
          from: GenServer.from(),
          payload: any,
          timeout_ref: reference
        }
end
