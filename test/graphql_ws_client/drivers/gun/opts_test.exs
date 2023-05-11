defmodule GraphQLWSClient.Drivers.Gun.OptsTest do
  use ExUnit.Case, async: true

  alias GraphQLWSClient.Drivers.Gun.Opts

  describe "new/1" do
    test "default options" do
      assert Opts.new(%{}) == %Opts{
               ack_timeout: :timer.seconds(5),
               adapter: :gun,
               connect_options: %{
                 connect_timeout: :timer.seconds(5),
                 protocols: [:http]
               },
               json_library: Jason,
               upgrade_timeout: :timer.seconds(5)
             }
    end

    test "merge connect options" do
      assert %Opts{connect_options: merged} =
               Opts.new(%{connect_options: %{connect_timeout: 1234}})

      assert merged == %{
               connect_timeout: 1234,
               protocols: [:http]
             }
    end
  end
end
