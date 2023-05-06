defmodule GraphQLWSClient.SocketError do
  @moduledoc """
  Exception that indicates a socket error.
  """

  defexception [:cause, :details]

  @type cause ::
          :connect
          | :closed
          | :critical_error
          | :unexpected_result
          | :status
          | :timeout

  @type t :: %__MODULE__{
          cause: cause,
          details: nil | %{optional(atom) => any}
        }

  def message(exception) do
    "GraphQL websocket error: " <>
      format_cause(exception.cause, exception.details)
  end

  defp format_cause(:connect, _), do: "Unable to connect to socket"

  defp format_cause(:closed, _), do: "Connection closed"

  defp format_cause(:critical_error, %{reason: reason}) do
    "Critical error (#{inspect(reason)})"
  end

  defp format_cause(:critical_error, _), do: "Critical error"

  defp format_cause(:unexpected_result, _), do: "Unexpected result"

  defp format_cause(:unexpected_status, %{code: code}) do
    "Unexpected status (#{code})"
  end

  defp format_cause(:timeout, _), do: "Connection timed out"
end
