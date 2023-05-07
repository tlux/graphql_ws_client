defmodule GraphQLWSClient.Driver do
  @moduledoc """
  A behaviour that defines function to implement custom backends.
  """

  alias GraphQLWSClient.{Config, Conn, Message, SocketError}

  @doc """
  Optional callback that prepares the `:opts` stored in the `#{inspect(Conn)}`.
  Can be used to set default values.
  """
  @callback init(opts :: map) :: map

  @doc """
  Connects to the socket and returns the updated `#{inspect(Conn)}`.
  """
  @callback connect(Conn.t()) :: {:ok, Conn.t()} | {:error, SocketError.t()}

  @doc """
  Disconnects from the socket.
  """
  @callback disconnect(Conn.t()) :: :ok

  @doc """
  Pushes a message to the socket.
  """
  @callback push_message(Conn.t(), msg :: Message.t()) :: :ok

  @doc """
  Parses a message received from the socket.
  """
  @callback parse_message(Conn.t(), msg :: any) ::
              {:ok, Message.t()} | {:error, SocketError.t()} | :ignore

  @optional_callbacks [init: 1]

  @doc false
  @spec connect(Config.t()) ::
          {:ok, Conn.t()} | {:error, SocketError.t()}
  def connect(%Config{driver: driver} = config) do
    {driver_mod, driver_opts} =
      case driver do
        {mod, opts} -> {mod, opts}
        mod -> {mod, %{}}
      end

    driver_mod.connect(%Conn{
      config: config,
      driver: driver_mod,
      opts: init_driver(driver_mod, driver_opts)
    })
  end

  defp init_driver(mod, opts) do
    opts = Map.new(opts)

    if Code.ensure_loaded?(mod) && function_exported?(mod, :init, 1) do
      mod.init(opts)
    else
      opts
    end
  end

  @doc false
  @spec disconnect(Conn.t()) :: :ok
  def disconnect(%Conn{driver: driver} = conn) do
    driver.disconnect(conn)
  end

  @doc false
  @spec push_message(Conn.t(), Message.t()) :: :ok
  def push_message(%Conn{driver: driver} = conn, %Message{} = msg) do
    driver.push_message(conn, msg)
  end

  @doc false
  @spec parse_message(Conn.t(), msg :: any) ::
          {:ok, Message.t()} | {:error, SocketError.t()} | :ignore
  def parse_message(%Conn{driver: driver} = conn, msg) do
    driver.parse_message(conn, msg)
  end
end
