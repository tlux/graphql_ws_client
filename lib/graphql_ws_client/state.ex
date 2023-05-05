defmodule GraphQLWSClient.State do
  @moduledoc false

  alias GraphQLWSClient.Config

  @type t :: %__MODULE__{
          config: Config.t(),
          connected?: boolean,
          listeners: %{optional(term) => pid},
          monitor_ref: reference,
          pid: pid,
          queries: %{optional(term) => GenServer.from()},
          stream_ref: reference
        }

  defstruct [
    :config,
    :monitor_ref,
    :pid,
    :stream_ref,
    connected?: false,
    listeners: %{},
    queries: %{}
  ]

  @spec fetch_subscription(t, term) ::
          {:ok, {:query, GenServer.from()}}
          | {:ok, {:listener, pid}}
          | :error
  def fetch_subscription(%__MODULE__{queries: queries}, id)
      when is_map_key(queries, id) do
    {:ok, {:query, Map.fetch!(queries, id)}}
  end

  def fetch_subscription(%__MODULE__{listeners: listeners}, id) do
    with {:ok, pid} <- Map.fetch(listeners, id) do
      {:ok, {:listener, pid}}
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
    listeners =
      state.listeners
      |> Enum.reject(fn
        {_, {_, ^pid}} -> true
        _ -> false
      end)
      |> Map.new()

    %{state | listeners: listeners}
  end

  @spec add_query(t, term, GenServer.from()) :: t
  def add_query(%__MODULE__{} = state, id, from) do
    %{state | queries: Map.put(state.queries, id, from)}
  end

  @spec remove_query(t, term) :: t
  def remove_query(%__MODULE__{} = state, id) do
    %{state | queries: Map.delete(state.queries, id)}
  end

  @spec remove_subscription(t, term) :: t
  def remove_subscription(%__MODULE__{} = state, id) do
    state
    |> remove_listener(id)
    |> remove_query(id)
  end

  @spec reset_queries(t) :: t
  def reset_queries(%__MODULE__{} = state) do
    %{state | queries: %{}}
  end
end
