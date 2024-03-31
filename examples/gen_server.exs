defmodule EventLogger do
  use GenServer

  alias GraphQLWSClient.Event

  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  @impl true
  def init(socket) do
    Process.flag(:trap_exit, true)

    subscription_id =
      GraphQLWSClient.subscribe!(socket, """
        subscription PostCreated {
          postCreated {
            id
            author
            body
          }
        }
      """)

    {:ok,
     %{
       socket: socket,
       subscription_id: subscription_id,
       monitor: Process.monitor(socket)
     }}
  end

  @impl true
  def terminate(_reason, %{socket: nil}), do: :ok

  def terminate(_reason, %{socket: socket, subscription_id: subscription_id}) do
    GraphQLWSClient.unsubscribe(socket, subscription_id)
  end

  @impl true
  def handle_info(
        {:DOWN, monitor, :process, socket, :normal},
        %{monitor: monitor, socket: socket} = state
      ) do
    IO.puts("Socket closed")
    {:stop, :normal, %{state | socket: nil, subscription_id: nil}}
  end

  def handle_info(
        %Event{type: :complete, subscription_id: subscription_id},
        %{subscription_id: subscription_id} = state
      ) do
    IO.puts("complete")
    {:noreply, state}
  end

  def handle_info(
        %Event{type: :next, subscription_id: subscription_id, payload: payload},
        %{subscription_id: subscription_id} = state
      ) do
    IO.inspect(payload)
    {:noreply, state}
  end

  def handle_info(
        %Event{type: :error, subscription_id: subscription_id, payload: error},
        %{subscription_id: subscription_id} = state
      ) do
    IO.inspect(error, label: "error")
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end

{:ok, socket} =
  GraphQLWSClient.start_link(url: "ws://localhost:8080/subscriptions")

EventLogger.start_link(socket)

Process.sleep(1000)

mutation = """
  mutation CreatePost($author: String!, $body: String!) {
    createPost(author: $author, body: $body) {
      id
    }
  }
"""

GraphQLWSClient.query!(socket, mutation, %{
  "author" => "Tobi",
  "body" => "Lorem Ipsum"
})

Process.sleep(1000)

GraphQLWSClient.query!(socket, mutation, %{
  "author" => "Casper",
  "body" => "What's up?"
})

Process.sleep(1000)

GenServer.stop(socket)
