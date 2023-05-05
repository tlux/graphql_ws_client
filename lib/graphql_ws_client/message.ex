defmodule GraphQLWSClient.Message do
  @moduledoc """
  A parsed message received by a driver.
  """

  @enforce_keys [:type, :id]

  defstruct [:type, :id, :payload]

  @type t :: %__MODULE__{
          type: :complete | :next | :error,
          id: term,
          payload: any
        }
end
