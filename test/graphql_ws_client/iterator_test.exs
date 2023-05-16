defmodule GraphQLWSClient.IteratorTest do
  use ExUnit.Case

  import Mox

  alias GraphQLWSClient.Config
  alias GraphQLWSClient.Conn
  alias GraphQLWSClient.Drivers.MockWithoutInit, as: MockDriver
  alias GraphQLWSClient.GraphQLError
  alias GraphQLWSClient.Iterator
  alias GraphQLWSClient.Iterator.Opts
  alias GraphQLWSClient.Message

  setup :set_mox_from_context
  setup :verify_on_exit!

  @config %Config{host: "localhost", port: 80, driver: MockDriver}
  @conn %Conn{config: @config, driver: MockDriver}
  @query "subscription Foo { foo { bar } }"
  @variables %{"foo" => "bar"}
  @payload_1 %{"bar" => "baz"}
  @payload_2 %{"baz" => 23}

  setup do
    test_pid = self()

    expect(MockDriver, :connect, fn @conn ->
      send(test_pid, :connected)
      {:ok, @conn}
    end)

    client = start_supervised!({GraphQLWSClient, @config}, id: :test_client)
    {:ok, client: client, test_pid: test_pid}
  end

  describe "open!/4" do
    test "success", %{client: client, test_pid: test_pid} do
      expect(MockDriver, :push_message, fn @conn,
                                           %Message{
                                             type: :subscribe,
                                             payload: %{
                                               query: @query,
                                               variables: @variables
                                             }
                                           } ->
        send(test_pid, :subscribed)
        :ok
      end)

      Iterator.open!(client, @query, @variables, buffer_size: :infinity)

      assert_receive :subscribed
    end

    test "non-numeric buffer size", %{client: client} do
      assert_receive :connected

      assert_raise ArgumentError, "invalid buffer size", fn ->
        Iterator.open!(client, @query, @variables, buffer_size: "__invalid__")
      end
    end

    test "negative buffer size", %{client: client} do
      assert_receive :connected

      assert_raise ArgumentError, "invalid buffer size", fn ->
        Iterator.open!(client, @query, @variables, buffer_size: -1)
      end
    end
  end

  describe "next/1" do
    setup %{client: client} do
      {:ok,
       opts: Opts.new(client: client, query: @query, variables: @variables)}
    end

    test "incomplete", %{client: client, opts: opts} do
      MockDriver
      |> expect(:push_message, fn @conn, %Message{id: id} ->
        send(client, {:next_msg, id})
        :ok
      end)
      |> expect(:parse_message, fn @conn, {:next_msg, id} ->
        send(self(), {:next_msg, id})
        {:ok, %Message{type: :next, id: id, payload: @payload_1}}
      end)
      |> expect(:parse_message, fn @conn, {:next_msg, id} ->
        {:ok, %Message{type: :next, id: id, payload: @payload_2}}
      end)

      iterator = start_supervised!({Iterator, opts})

      assert Iterator.next(iterator) == [@payload_1]
      assert Iterator.next(iterator) == [@payload_2]

      # blocks caller when no results available
      task = Task.async(fn -> Iterator.next(iterator) end)

      assert (Task.yield(task, 250) || Task.shutdown(task)) == nil
    end

    test "limited buffer", %{client: client, opts: opts} do
      test_pid = self()

      MockDriver
      |> expect(:push_message, fn @conn, %Message{id: id} ->
        send(client, {:next_msg, id})
        :ok
      end)
      |> expect(:parse_message, 5, fn @conn, {:next_msg, id} ->
        send(self(), {:next_msg, id})
        {:ok, %Message{type: :next, id: id, payload: @payload_1}}
      end)
      |> expect(:parse_message, fn @conn, {:next_msg, id} ->
        send(self(), {:complete_msg, id})
        {:ok, %Message{type: :next, id: id, payload: @payload_2}}
      end)
      |> expect(:parse_message, fn @conn, {:complete_msg, id} ->
        send(test_pid, :completed)
        {:ok, %Message{type: :complete, id: id}}
      end)

      iterator = start_supervised!({Iterator, %{opts | buffer_size: 3}})

      assert_receive :completed
      assert Iterator.next(iterator) == [@payload_1, @payload_1, @payload_2]
      assert Iterator.next(iterator) == :halt
      assert Iterator.next(iterator) == :halt
    end

    test "unlimited buffer", %{opts: opts} do
      test_pid = self()

      MockDriver
      |> expect(:push_message, fn @conn, %Message{id: id} ->
        send(self(), {:next_msg, id})
        :ok
      end)
      |> expect(:parse_message, 5, fn @conn, {:next_msg, id} ->
        send(self(), {:next_msg, id})
        {:ok, %Message{type: :next, id: id, payload: @payload_1}}
      end)
      |> expect(:parse_message, fn @conn, {:next_msg, id} ->
        send(self(), {:complete_msg, id})
        {:ok, %Message{type: :next, id: id, payload: @payload_2}}
      end)
      |> expect(:parse_message, fn @conn, {:complete_msg, id} ->
        send(test_pid, :completed)
        {:ok, %Message{type: :complete, id: id}}
      end)

      iterator = start_supervised!({Iterator, %{opts | buffer_size: :infinity}})

      assert_receive :completed

      assert Iterator.next(iterator) == [
               @payload_1,
               @payload_1,
               @payload_1,
               @payload_1,
               @payload_1,
               @payload_2
             ]

      assert Iterator.next(iterator) == :halt
    end

    test "GraphQL error", %{opts: opts} do
      test_pid = self()
      errors = [%{"message" => "Something went wrong"}]

      MockDriver
      |> expect(:push_message, fn @conn, %Message{id: id} ->
        send(test_pid, {:subscribed, id})
        send(self(), {:next_msg, id})
        :ok
      end)
      |> expect(:parse_message, fn @conn, {:next_msg, id} ->
        {:ok, %Message{type: :error, id: id, payload: errors}}
      end)
      |> expect(:push_message, fn @conn, %Message{type: :complete, id: id} ->
        send(test_pid, {:completed, id})
        :ok
      end)

      iterator = start_supervised!({Iterator, opts})

      assert_receive {:subscribed, id}
      assert_receive {:completed, ^id}

      try do
        Iterator.next(iterator)
        flunk("expected next/1 to exit")
      catch
        :exit, {{:error, error}, _} ->
          assert error == %GraphQLError{errors: errors}
      end
    end

    test "client crashed", %{opts: opts} do
      test_pid = self()

      expect(MockDriver, :push_message, fn @conn, _ ->
        send(test_pid, :subscribed)
        :ok
      end)

      iterator = start_supervised!({Iterator, opts})

      assert_receive :subscribed

      task =
        Task.async(fn ->
          send(test_pid, :task_started)
          Iterator.next(iterator)
        end)

      assert_receive :task_started
      stop_supervised!(:test_client)

      assert Task.await(task) == :halt
    end
  end
end
