defmodule GraphQLWSClient.State.Listener do
  @moduledoc false

  @enforce_keys [:id, :pid, :monitor_ref, :payload]

  defstruct [:id, :pid, :monitor_ref, :payload]

  @type t :: %__MODULE__{
          id: term,
          pid: pid,
          monitor_ref: reference,
          payload: any
        }
end
