defmodule GraphQLWSClient.Driver do
  alias GraphQLWSClient.{Config, Conn}

  @type conn :: any

  @callback connect(Config.t()) :: {:ok, conn} | {:error, Exception.t()}
  @callback disconnect(conn) :: :ok

  @spec connect(Config.t()) :: Conn.t()
  def connect(%Config{driver: driver} = config) do
    with {:ok, conn} <- driver.connect(config) do
      {:ok, %Conn{config: config, conn: conn}}
    end
  end

  @spec disconnect(Conn.t()) :: :ok
  def disconnect(%Conn{config: config, conn: conn}) do
    config.driver.disconnect(conn)
  end
end
