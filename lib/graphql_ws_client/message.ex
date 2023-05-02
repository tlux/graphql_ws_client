defmodule GraphQLWSClient.Message do
  @moduledoc """
  A message for a subscription.
  """

  defstruct [:subscription_id, :payload]

  def new(subscription_id, payload) do
    %__MODULE__{subscription_id: subscription_id, payload: payload}
  end
end
