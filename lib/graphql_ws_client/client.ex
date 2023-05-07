defmodule GraphQLWSClient.Client do
  @moduledoc """
  A behaviour that is implemented by modules that `use GraphQLWSClient`.
  """

  @doc """
  Starts the client.
  """
  @callback start_link(GenServer.options()) :: GenServer.on_start()

  @doc """
  Connects to the server.
  """
  @callback open(timeout) :: :ok | {:error, Exception.t()}

  @doc """
  Connects to the server. Raises on error
  """
  @callback open!(timeout) :: :ok | no_return

  @doc """
  Closes the connection to the server.
  """
  @callback close(timeout) :: :ok

  @doc """
  Sends a query to the server and returns the result.
  """
  @callback query(GraphQLWSClient.query(), map, timeout) ::
              {:ok, any} | {:error, Exception.t()}

  @doc """
  Sends a query to the server and returns the result. Raises on error.
  """
  @callback query!(GraphQLWSClient.query(), map, timeout) :: any | no_return

  @doc """
  Sends a subscription to the server and returns the subscription ID.
  """
  @callback subscribe(GraphQLWSClient.query(), map, pid, timeout) ::
              {:ok, GraphQLWSClient.subscription_id()} | {:error, Exception.t()}

  @doc """
  Sends a subscription to the server and returns the subscription ID. Raises on
  error.
  """
  @callback subscribe!(GraphQLWSClient.query(), map, pid, timeout) ::
              GraphQLWSClient.subscription_id() | no_return

  @doc """
  Removes the subscription for the given subscription ID.
  """
  @callback unsubscribe(GraphQLWSClient.subscription_id(), timeout) ::
              :ok | {:error, Exception.t()}

  @doc """
  Removes the subscription for the given subscription ID. Raises on error.
  """
  @callback unsubscribe!(GraphQLWSClient.subscription_id(), timeout) ::
              :ok | no_return
end
