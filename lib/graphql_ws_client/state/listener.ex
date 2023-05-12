defmodule GraphQLWSClient.State.Listener do
  @moduledoc false

  @enforce_keys [:id, :pid, :monitor_ref]

  defstruct [:id, :pid, :monitor_ref]

  @type t :: %__MODULE__{
          id: term,
          pid: pid,
          monitor_ref: reference
        }
end
