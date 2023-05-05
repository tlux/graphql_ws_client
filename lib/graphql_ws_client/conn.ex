defmodule GraphQLWSClient.Conn do
  @moduledoc false

  @enforce_keys [:json_library, :pid, :stream_ref]

  defstruct [:json_library, :pid, :stream_ref]

  @type t :: %__MODULE__{
          json_library: module,
          pid: pid,
          stream_ref: reference
        }
end
