defmodule GraphQLWSClient.Event do
  @moduledoc """
  A event for a subscription.
  """

  defstruct [:error, :subscription_id, :result, :status]

  @type t ::
          %__MODULE__{
            error: nil,
            subscription_id: GraphQLWSClient.subscription_id(),
            result: any,
            status: :ok
          }
          | %__MODULE__{
              error: Exception.t(),
              subscription_id: GraphQLWSClient.subscription_id(),
              result: nil,
              status: :error
            }
end
