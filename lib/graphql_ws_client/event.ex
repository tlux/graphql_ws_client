defmodule GraphQLWSClient.Event do
  @moduledoc """
  A event for a subscription.
  """

  alias GraphQLWSClient.QueryError

  defstruct [:subscription_id, :data, :error]

  @type t :: %__MODULE__{
          subscription_id: GraphQLWSClient.subscription_id(),
          data: any,
          error: nil | QueryError.t()
        }
end
