defmodule GraphQLWSClient.State do
  @moduledoc false

  alias GraphQLWSClient.{Config, Conn}
  alias GraphQLWSClient.State.{Listener, Query}

  @type t :: %__MODULE__{
          config: Config.t(),
          conn: nil | Conn.t(),
          connected?: boolean,
          init_payload: any,
          listeners: %{optional(term) => Listener.t()},
          monitor_ref: nil | reference,
          queries: %{optional(term) => Query.t()}
        }

  defstruct [
    :config,
    :conn,
    :init_payload,
    :monitor_ref,
    connected?: false,
    listeners: %{},
    queries: %{}
  ]

  @spec put_conn(t, Conn.t(), reference) :: t
  def put_conn(%__MODULE__{} = state, conn, monitor_ref) do
    %{
      state
      | connected?: true,
        conn: conn,
        monitor_ref: monitor_ref
    }
  end

  @spec reset_conn(t) :: t
  def reset_conn(%__MODULE__{} = state) do
    %{
      state
      | connected?: false,
        conn: nil,
        monitor_ref: nil
    }
  end

  @spec fetch_subscription(t, term) :: {:ok, Listener.t() | Query.t()} | :error
  def fetch_subscription(%__MODULE__{queries: queries}, id)
      when is_map_key(queries, id) do
    {:ok, Map.fetch!(queries, id)}
  end

  def fetch_subscription(%__MODULE__{listeners: listeners}, id) do
    Map.fetch(listeners, id)
  end

  @spec fetch_listener_by_monitor(t, reference) :: {:ok, Listener.t()} | :error
  def fetch_listener_by_monitor(%__MODULE__{listeners: listeners}, monitor_ref) do
    Enum.find_value(listeners, :error, fn
      {_, %Listener{monitor_ref: ^monitor_ref} = listener} -> {:ok, listener}
      _ -> nil
    end)
  end

  @spec put_listener(t, Listener.t()) :: t
  def put_listener(%__MODULE__{} = state, %Listener{id: id} = listener) do
    %{state | listeners: Map.put(state.listeners, id, listener)}
  end

  @spec put_query(t, Query.t()) :: t
  def put_query(%__MODULE__{} = state, %Query{id: id} = query) do
    %{state | queries: Map.put(state.queries, id, query)}
  end

  @spec remove_listener(t, term) :: t
  def remove_listener(%__MODULE__{} = state, id) do
    %{state | listeners: Map.delete(state.listeners, id)}
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
