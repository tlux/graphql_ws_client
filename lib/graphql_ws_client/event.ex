defmodule GraphQLWSClient.Event do
  @moduledoc """
  A event for a subscription.

  The struct consists of these fields:

  * `:subscription_id` - A UUID identifying the subscription. This matches the
    subscription ID that is returned by `GraphQLWSClient.subscribe/3`.
  * `:status` - Indicates whether the event contains the result data (`:ok`) or
    an error (`:error`).
  * `:result` - The payload, either the result or error data, dependent on the
    `:status` field.
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
