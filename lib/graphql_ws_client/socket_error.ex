defmodule GraphQLWSClient.SocketError do
  @moduledoc """
  Exception that indicates a socket error.
  """

  defexception [:cause, :details]

  @type cause :: :connect | :closed | :result | :timeout

  @type t :: %__MODULE__{
          cause: cause,
          details: nil | %{optional(atom) => any}
        }

  def message(exception) do
    "GraphQL websocket error: #{format_cause(exception.cause)}"
  end

  defp format_cause(:connect), do: "Unable to connect to socket"
  defp format_cause(:closed), do: "Connection closed"
  defp format_cause(:result), do: "Unexpected result"
  defp format_cause(:timeout), do: "Connection timed out"
end
