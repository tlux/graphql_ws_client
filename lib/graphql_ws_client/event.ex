defmodule GraphQLWSClient.Event do
  @moduledoc """
  A event for a subscription.
  """

  defstruct [:subscription_id, :result, :status]

  @type ok :: %__MODULE__{
          subscription_id: GraphQLWSClient.subscription_id(),
          result: any,
          status: :ok
        }

  @type error :: %__MODULE__{
          subscription_id: GraphQLWSClient.subscription_id(),
          result: Exception.t(),
          status: :error
        }

  @type t :: ok | error
end
