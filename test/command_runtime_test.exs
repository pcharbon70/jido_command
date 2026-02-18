defmodule JidoCommand.Extensibility.CommandRuntimeTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoCommand.Extensibility.CommandDefinition
  alias JidoCommand.Extensibility.CommandRuntime

  defmodule FailingExecutor do
    @behaviour JidoCommand.Extensibility.CommandRuntime

    @impl true
    def execute(_definition, _prompt, _params, _context), do: {:error, :boom}
  end

  test "emits pre and after hooks on success" do
    bus = unique_bus_name()
    start_supervised!({Bus, name: bus})

    {:ok, _pre} =
      Bus.subscribe(bus, "commands.test.pre", dispatch: {:pid, target: self()})

    {:ok, _after} =
      Bus.subscribe(bus, "commands.test.after", dispatch: {:pid, target: self()})

    definition = %CommandDefinition{
      name: "test",
      description: "test",
      hooks: %{pre: "commands/test/pre", after: "commands/test/after"},
      body: "hello {{name}}"
    }

    assert {:ok, result} = CommandRuntime.execute(definition, %{"name" => "Pascal"}, %{bus: bus})
    assert result["result"]["prompt"] == "hello Pascal"

    assert_receive {:signal, %Signal{type: "commands.test.pre", data: pre_data}}, 1_000
    assert pre_data["status"] == "pre"

    assert_receive {:signal, %Signal{type: "commands.test.after", data: after_data}}, 1_000
    assert after_data["status"] == "ok"
  end

  test "emits after hook on error" do
    bus = unique_bus_name()
    start_supervised!({Bus, name: bus})

    {:ok, _after} =
      Bus.subscribe(bus, "commands.test.after", dispatch: {:pid, target: self()})

    definition = %CommandDefinition{
      name: "test",
      description: "test",
      hooks: %{pre: nil, after: "commands/test/after"},
      body: "ignored"
    }

    assert {:error, :boom} =
             CommandRuntime.execute(definition, %{}, %{
               bus: bus,
               command_executor: FailingExecutor
             })

    assert_receive {:signal, %Signal{type: "commands.test.after", data: after_data}}, 1_000
    assert after_data["status"] == "error"
  end

  defp unique_bus_name do
    :"jido_command_runtime_bus_#{System.unique_integer([:positive, :monotonic])}"
  end
end
