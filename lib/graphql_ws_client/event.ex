defmodule GraphQLWSClient.Event do
  @moduledoc """
  A event for a subscription.

  The struct consists of these fields:

  * `:payload` - Either the result, an error or `nil`, dependent on the `:type`
    field.
  * `:subscription_id` - A UUID identifying the subscription. This matches the
    subscription ID that is returned by `GraphQLWSClient.subscribe/3`.
  * `:type` - Indicates whether the event contains payload data (`:next`), there
    is no more data to receive (`:complete`) or an error occurred (`:error`).
  """

  defstruct [:payload, :subscription_id, :type]

  @type complete :: %__MODULE__{
          payload: nil,
          subscription_id: GraphQLWSClient.subscription_id(),
          type: :complete
        }

  @type error :: %__MODULE__{
          payload: Exception.t(),
          subscription_id: GraphQLWSClient.subscription_id(),
          type: :error
        }

  @type next :: %__MODULE__{
          payload: any,
          subscription_id: GraphQLWSClient.subscription_id(),
          type: :next
        }

  @type t :: complete | error | next
end
