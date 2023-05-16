defmodule GraphQLWSClient.Iterator.State do
  @moduledoc false

  @enforce_keys [:buffer_size, :client, :monitor_ref]

  defstruct [
    :buffer_size,
    :client,
    :from,
    :monitor_ref,
    :subscription_id,
    buffer: [],
    halted?: false
  ]
end
