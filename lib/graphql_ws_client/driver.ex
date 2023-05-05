defmodule GraphQLWSClient.Driver do
  @moduledoc """
  A behaviour that defines function to implement own backends.
  """

  alias GraphQLWSClient.{Config, Conn, Message, SocketError}

  @callback connect(Config.t()) :: {:ok, Conn.t()} | {:error, SocketError.t()}

  @callback disconnect(Conn.t()) :: :ok

  @callback push_message(Conn.t(), msg :: any) :: :ok

  @callback handle_message(Conn.t(), msg :: any) ::
              {:ok, Message.t()} | {:error, SocketError.t()} | :ignore
end
