defmodule GraphQLWSClient.Message do
  @moduledoc """
  A message passed received by a driver.
  """

  @enforce_keys [:type]

  defstruct [:type, :id, :payload]

  @type message_type ::
          :complete
          | :connection_ack
          | :connection_init
          | :error
          | :next
          | :subscribe

  @type t :: %__MODULE__{type: message_type, id: term, payload: any}

  @valid_types ~w(complete connection_ack connection_init error next subscribe)

  @doc false
  @spec parse(String.t(), module) :: {:ok, t} | :error
  def parse(value, decoder) do
    case decoder.decode(value) do
      {:ok, %{"type" => type} = data} when type in @valid_types ->
        {:ok,
         %__MODULE__{
           type: String.to_existing_atom(type),
           id: data["id"],
           payload: data["payload"]
         }}

      _ ->
        :error
    end
  end

  @doc false
  @spec serialize(t, module) :: String.t()
  def serialize(%__MODULE__{} = message, encoder) do
    message
    |> Map.from_struct()
    |> delete_empty(:id)
    |> delete_empty(:payload)
    |> encoder.encode!()
  end

  defp delete_empty(map, field) do
    case Map.fetch(map, field) do
      {:ok, nil} -> Map.delete(map, field)
      _ -> map
    end
  end
end
