defmodule GraphQLWSClient.Driver do
  @moduledoc """
  A behaviour that defines function to implement custom backends.
  """

  alias GraphQLWSClient.{Config, Conn, Message, SocketError}

  @callback connect(Conn.disconnected()) ::
              {:ok, Conn.connected()}
              | {:error, SocketError.t()}

  @callback disconnect(Conn.connected()) :: :ok

  @callback push_message(Conn.connected(), msg :: any) :: :ok

  @callback handle_message(Conn.connected(), msg :: any) ::
              {:ok, Message.t()} | {:error, SocketError.t()} | :ignore

  @doc false
  @spec connect(Config.t()) ::
          {:ok, Conn.connected()} | {:error, SocketError.t()}
  def connect(%Config{driver: {driver_mod, driver_opts}} = config) do
    driver_mod.connect(%Conn{config: config, opts: Map.new(driver_opts)})
  end

  def connect(%Config{driver: driver_mod} = config) do
    driver_mod.connect(%Conn{config: config, opts: %{}})
  end
end
