defmodule GraphQLWSClient.MessageTest do
  use ExUnit.Case, async: true

  alias GraphQLWSClient.Message

  describe "parse/2" do
    @payload %{"foo" => "bar"}

    Enum.each(
      ~w(complete connection_ack connection_init error next subscribe),
      fn type ->
        test type do
          value =
            Jason.encode!(%{
              "type" => unquote(type),
              "id" => "__id__",
              "payload" => @payload
            })

          assert Message.parse(value, Jason) ==
                   {:ok,
                    %Message{
                      id: "__id__",
                      type: String.to_atom(unquote(type)),
                      payload: @payload
                    }}
        end
      end
    )

    test "invalid type" do
      value =
        Jason.encode!(%{
          "type" => "invalid",
          "id" => "__id__",
          "payload" => @payload
        })

      assert Message.parse(value, Jason) == :error
    end
  end

  describe "serialize/2" do
    test "without payload" do
      assert Message.serialize(
               %Message{id: "__id__", type: :complete},
               Jason
             ) ==
               Jason.encode!(%{"id" => "__id__", "type" => "complete"})
    end

    test "with payload" do
      assert Message.serialize(
               %Message{
                 id: "__id__",
                 type: :subscribe,
                 payload: %{query: "__query__", variables: %{"foo" => "bar"}}
               },
               Jason
             ) ==
               Jason.encode!(%{
                 "id" => "__id__",
                 "type" => "subscribe",
                 "payload" => %{
                   "query" => "__query__",
                   "variables" => %{"foo" => "bar"}
                 }
               })
    end
  end
end
