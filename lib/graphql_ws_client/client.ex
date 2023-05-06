defmodule GraphQLWSClient.Client do
  @moduledoc """
  A behaviour that is implemented by modules that `use GraphQLWSClient`.
  """

  @callback start_link(GenServer.options()) :: GenServer.on_start()

  @callback open(timeout) :: :ok | {:error, Exception.t()}

  @callback close(timeout) :: :ok

  @callback query(GraphQLWSClient.query(), map, timeout) ::
              {:ok, any} | {:error, Exception.t()}

  @callback query!(GraphQLWSClient.query(), map, timeout) :: any | no_return

  @callback subscribe(GraphQLWSClient.query(), map, pid, timeout) ::
              {:ok, GraphQLWSClient.subscription_id()} | {:error, Exception.t()}

  @callback unsubscribe(GraphQLWSClient.subscription_id(), timeout) :: :ok
end
