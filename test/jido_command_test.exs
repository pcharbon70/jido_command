defmodule JidoCommandTest do
  use ExUnit.Case

  test "dispatch publishes command.invoke signal" do
    bus = unique_bus_name()
    start_supervised!({Jido.Signal.Bus, name: bus})

    {:ok, _subscription} =
      Jido.Signal.Bus.subscribe(bus, "command.invoke", dispatch: {:pid, target: self()})

    assert {:ok, invocation_id} = JidoCommand.dispatch("demo", %{"x" => 1}, %{}, bus: bus)
    assert is_binary(invocation_id)

    assert_receive {:signal, %Jido.Signal{type: "command.invoke", data: data}}, 1_000
    assert data["name"] == "demo"
    assert data["params"] == %{"x" => 1}
    assert data["invocation_id"] == invocation_id
  end

  defp unique_bus_name do
    :"jido_command_test_bus_#{System.unique_integer([:positive, :monotonic])}"
  end
end
