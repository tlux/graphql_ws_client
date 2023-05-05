defmodule GraphQLWSClient.Conn do
  defstruct [:config, :conn]

  @type t :: %__MODULE__{config: Config.t(), conn: any}
end
