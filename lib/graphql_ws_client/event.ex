defmodule GraphQLWSClient.Event do
  @moduledoc """
  A event for a subscription.
  """

  alias GraphQLWSClient.QueryError

  defstruct [:subscription_id, :result, :error]

  @type t :: %__MODULE__{
          subscription_id: GraphQLWSClient.subscription_id(),
          result: nil | any,
          error: nil | QueryError.t()
        }
end
