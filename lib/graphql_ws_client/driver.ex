defmodule GraphQLWSClient.Driver do
  @moduledoc """
  A behaviour that defines function to implement custom backends.
  """

  alias GraphQLWSClient.{Config, Conn, Message, SocketError}

  @doc """
  Connects to the socket and returns the updated `#{inspect(Conn)}`.
  """
  @callback connect(Conn.disconnected()) ::
              {:ok, Conn.connected()}
              | {:error, SocketError.t()}

  @doc """
  Disconnects from the socket.
  """
  @callback disconnect(Conn.connected()) :: :ok

  @doc """
  Pushes a message to the socket.
  """
  @callback push_message(Conn.connected(), msg :: any) :: :ok

  @doc """
  Parses a message received from the socket.
  """
  @callback handle_message(Conn.connected(), msg :: any) ::
              {:ok, Message.t()} | {:error, SocketError.t()} | :ignore

  @doc false
  @spec connect(Config.t()) ::
          {:ok, Conn.connected()} | {:error, SocketError.t()}
  def connect(%Config{driver: driver} = config) do
    {driver_mod, driver_opts} =
      case driver do
        {mod, opts} -> {mod, Map.new(opts)}
        mod -> {mod, %{}}
      end

    driver_mod.connect(%Conn{config: config, opts: driver_opts})
  end

  @doc false
  @spec disconnect(Conn.connected()) :: :ok
  def disconnect(%Conn{config: %Config{driver: driver}} = conn) do
    driver_mod =
      case driver do
        {mod, _} -> mod
        mod -> mod
      end

    driver_mod.disconnect(conn)
  end
end
