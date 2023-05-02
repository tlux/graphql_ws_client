defmodule GraphQLWSClient.State do
  @moduledoc false

  alias GraphQLWSClient.Options

  @type t :: %__MODULE__{
          options: Options.t(),
          pid: pid,
          monitor_ref: reference,
          stream_ref: reference,
          listeners: %{optional(term) => pid},
          queries: %{optional(String.t()) => GenServer.from()}
        }

  defstruct [
    :options,
    :pid,
    :monitor_ref,
    :stream_ref,
    listeners: %{},
    queries: %{}
  ]

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
    # TODO: Optimize
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

  @spec register_query(t, term, GenServer.from()) :: t
  def register_query(%__MODULE__{} = state, id, from) do
    %{state | queries: Map.put(state.queries, id, from)}
  end

  @spec unregister_query(t, term) :: t
  def unregister_query(%__MODULE__{} = state, id) do
    %{state | queries: Map.delete(state.queries, id)}
  end

  @spec pop_query!(t, term) :: {GenServer.from(), t} | no_return
  def pop_query!(%__MODULE__{} = state, id) do
    {from, queries} = Map.pop!(state.queries, id)
    {from, %{state | queries: queries}}
  end
end
