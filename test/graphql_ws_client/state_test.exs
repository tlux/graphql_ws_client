defmodule GraphQLWSClient.StateTest do
  use ExUnit.Case, async: true

  alias GraphQLWSClient.Config
  alias GraphQLWSClient.Conn
  alias GraphQLWSClient.State

  @conn %Conn{
    config: %Config{host: "localhost", port: 80},
    driver: NonExistentDriver
  }

  describe "put_conn/3" do
    test "set connected? to true" do
      fake_monitor_ref = make_ref()

      assert State.put_conn(
               %State{connected?: false},
               @conn,
               fake_monitor_ref
             ) == %State{
               connected?: true,
               conn: @conn,
               monitor_ref: fake_monitor_ref
             }
    end
  end

  describe "reset_conn/1" do
    test "set connected? to false" do
      assert State.reset_conn(%State{
               connected?: true,
               conn: @conn,
               monitor_ref: make_ref()
             }) == %State{connected?: false, conn: nil, monitor_ref: nil}
    end
  end

  describe "fetch_subscription/2" do
    setup do
      listener = build_listener()
      query = build_query()

      state =
        %State{}
        |> State.put_listener(listener)
        |> State.put_query(query)

      {:ok, state: state, query: query, listener: listener}
    end

    test "get query", %{state: state, query: query} do
      assert State.fetch_subscription(state, query.id) == {:ok, query}
    end

    test "get listener", %{state: state, listener: listener} do
      assert State.fetch_subscription(state, listener.id) == {:ok, listener}
    end

    test "not found", %{state: state} do
      assert State.fetch_subscription(state, "__invalid__") == :error
    end
  end

  describe "fetch_listener_by_monitor/2" do
    setup do
      listener = build_listener()
      state = State.put_listener(%State{}, listener)

      {:ok, state: state, listener: listener}
    end

    test "found", %{state: state, listener: listener} do
      assert State.fetch_listener_by_monitor(state, listener.monitor_ref) ==
               {:ok, listener}
    end

    test "not found", %{state: state} do
      assert State.fetch_listener_by_monitor(state, make_ref()) == :error
    end
  end

  describe "put_listener/2" do
    test "put entry" do
      listener = build_listener()
      state = State.put_listener(%State{}, listener)

      assert state.listeners[listener.id] == listener
    end
  end

  describe "put_query/2" do
    test "put entry" do
      query = build_query()
      state = State.put_query(%State{}, query)

      assert state.queries[query.id] == query
    end
  end

  describe "remove_listener/2" do
    test "remove entry" do
      listener = build_listener()
      other_id = UUID.uuid4()

      assert State.remove_listener(
               %State{
                 listeners: %{listener.id => listener, other_id => listener}
               },
               listener.id
             ) == %State{listeners: %{other_id => listener}}
    end
  end

  describe "remove_query/2" do
    test "remove entry" do
      query = build_query()
      other_id = UUID.uuid4()

      assert State.remove_query(
               %State{queries: %{query.id => query, other_id => query}},
               query.id
             ) == %State{queries: %{other_id => query}}
    end
  end

  describe "remove_subscription/2" do
    test "remove entries" do
      id = UUID.uuid4()
      other_id = UUID.uuid4()
      listener = %{build_listener() | id: id}
      query = %{build_query() | id: id}

      assert State.remove_subscription(
               %State{
                 listeners: %{id => listener, other_id => listener},
                 queries: %{id => query, other_id => query}
               },
               id
             ) == %State{
               listeners: %{other_id => listener},
               queries: %{other_id => query}
             }
    end
  end

  describe "reset_subscriptions/1" do
    test "remove all entries" do
      state =
        %State{}
        |> State.put_listener(build_listener())
        |> State.put_listener(build_listener())
        |> State.put_query(build_query())
        |> State.put_query(build_query())

      assert State.reset_subscriptions(state) == %State{
               listeners: %{},
               queries: %{}
             }
    end
  end

  defp build_listener do
    %State.Listener{
      id: UUID.uuid4(),
      pid: self(),
      monitor_ref: make_ref()
    }
  end

  defp build_query do
    %State.Query{
      id: UUID.uuid4(),
      from: {make_ref(), self()},
      timeout_ref: make_ref()
    }
  end
end
