defmodule GraphQLWSClient.State do
  @moduledoc false

  alias GraphQLWSClient.Options

  @type t :: %__MODULE__{
          options: Options.t(),
          pid: pid,
          monitor_ref: reference,
          stream_ref: reference,
          listeners: %{optional(term) => pid},
          queries: %{optional(term) => GenServer.from()}
        }

  defstruct [
    :options,
    :pid,
    :monitor_ref,
    :stream_ref,
    listeners: %{},
    queries: %{}
  ]

  @spec fetch_subscription(t, term) ::
          {:ok, {:listener, pid}} | {:ok, {:query, GenServer.from()}} | :error
  def fetch_subscription(%__MODULE__{listeners: listeners}, id)
      when is_map_key(listeners, id) do
    {:ok, {:listener, Map.fetch!(listeners, id)}}
  end

  def fetch_subscription(%__MODULE__{queries: queries}, id) do
    case Map.fetch(queries, id) do
      {:ok, recipient} -> {:ok, {:query, recipient}}
      :error -> :error
    end
  end

  @spec add_listener(t, term, pid) :: t
  def add_listener(%__MODULE__{} = state, id, listener) do
    %{state | listeners: Map.put(state.listeners, id, listener)}
  end

  @spec remove_listener(t, term) :: t
  def remove_listener(%__MODULE__{} = state, id) do
    %{state | listeners: Map.delete(state.listeners, id)}
  end

  @spec remove_listener_by_pid(t, pid) :: t
  def remove_listener_by_pid(%__MODULE__{} = state, pid) do
    # TODO: Optimize?
    %{
      state
      | listeners:
          state.listeners
          |> Enum.reject(fn
            {_, ^pid} -> true
            _ -> false
          end)
          |> Map.new()
    }
  end

  @spec add_query(t, term, GenServer.from()) :: t
  def add_query(%__MODULE__{} = state, id, from) do
    %{state | queries: Map.put(state.queries, id, from)}
  end

  @spec remove_query(t, term) :: t
  def remove_query(%__MODULE__{} = state, id) do
    %{state | queries: Map.delete(state.queries, id)}
  end
end
