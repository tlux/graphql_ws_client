defmodule GraphQLWSClient.Message do
  @enforce_keys [:type, :id]

  defstruct [:type, :id, :payload]

  @type t :: %__MODULE__{
          type: :complete | :next | :error,
          id: term,
          payload: any
        }
end
