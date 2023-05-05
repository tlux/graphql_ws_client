defmodule GraphQLWSClient.Driver do
  @moduledoc false

  alias GraphQLWSClient.{Config, Message, SocketError}

  @type conn :: any

  @callback connect(Config.t()) :: {:ok, conn} | {:error, SocketError.t()}

  @callback disconnect(conn) :: :ok

  @callback push_message(conn, msg :: any) :: :ok

  @callback handle_message(conn, msg :: any) ::
              {:ok, Message.t()} | {:error, SocketError.t()} | :ignore
end
