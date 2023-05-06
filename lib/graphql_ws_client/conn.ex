defmodule GraphQLWSClient.Conn do
  @moduledoc false

  @enforce_keys [:config, :opts]

  defstruct [:config, :opts, :pid, :stream_ref]

  @type opts :: %{optional(atom) => any}

  @type disconnected :: %__MODULE__{
          config: Config.t(),
          opts: opts,
          pid: nil,
          stream_ref: nil
        }

  @type connected :: %__MODULE__{
          config: Config.t(),
          opts: opts,
          pid: pid,
          stream_ref: reference
        }

  @type t :: disconnected | connected
end
