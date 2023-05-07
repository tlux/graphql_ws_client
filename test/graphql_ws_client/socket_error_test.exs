defmodule GraphQLWSClient.SocketErrorTest do
  use ExUnit.Case, async: true

  alias GraphQLWSClient.SocketError

  describe "Exception.message/1" do
    test "connect error" do
      assert Exception.message(%SocketError{cause: :connect}) ==
               "GraphQL websocket error: Unable to connect to socket"
    end

    test "closed error" do
      assert Exception.message(%SocketError{cause: :closed}) ==
               "GraphQL websocket error: Connection closed"
    end

    test "critical error with reason" do
      assert Exception.message(%SocketError{
               cause: :critical_error,
               details: %{reason: "ooops"}
             }) == ~s[GraphQL websocket error: Critical error ("ooops")]
    end

    test "critical error without reason" do
      assert Exception.message(%SocketError{cause: :critical_error}) ==
               "GraphQL websocket error: Critical error"
    end

    test "unexpected result" do
      assert Exception.message(%SocketError{cause: :unexpected_result}) ==
               "GraphQL websocket error: Unexpected result"
    end

    test "unexpected status" do
      assert Exception.message(%SocketError{
               cause: :unexpected_status,
               details: %{code: 400}
             }) == "GraphQL websocket error: Unexpected status (400)"
    end

    test "timeout" do
      assert Exception.message(%SocketError{cause: :timeout}) ==
               "GraphQL websocket error: Connection timed out"
    end
  end
end
