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
      Bus.subscribe(bus, "jido.hooks.pre", dispatch: {:pid, target: self()})

    {:ok, _after} =
      Bus.subscribe(bus, "jido.hooks.after", dispatch: {:pid, target: self()})

    definition = %CommandDefinition{
      name: "test",
      description: "test",
      hooks: %{pre: true, after: true},
      body: "hello {{name}}"
    }

    assert {:ok, result} = CommandRuntime.execute(definition, %{"name" => "Pascal"}, %{bus: bus})
    assert result["result"]["prompt"] == "hello Pascal"

    assert_receive {:signal, %Signal{type: "jido.hooks.pre", data: pre_data}}, 1_000
    assert pre_data["status"] == "pre"

    assert_receive {:signal, %Signal{type: "jido.hooks.after", data: after_data}}, 1_000
    assert after_data["status"] == "ok"
  end

  test "emits after hook on error" do
    bus = unique_bus_name()
    start_supervised!({Bus, name: bus})

    {:ok, _after} =
      Bus.subscribe(bus, "jido.hooks.after", dispatch: {:pid, target: self()})

    definition = %CommandDefinition{
      name: "test",
      description: "test",
      hooks: %{pre: false, after: true},
      body: "ignored"
    }

    assert {:error, :boom} =
             CommandRuntime.execute(definition, %{}, %{
               bus: bus,
               command_executor: FailingExecutor
             })

    assert_receive {:signal, %Signal{type: "jido.hooks.after", data: after_data}}, 1_000
    assert after_data["status"] == "error"
  end

  test "does not emit hooks when both hook flags are disabled" do
    bus = unique_bus_name()
    start_supervised!({Bus, name: bus})

    {:ok, _pre} =
      Bus.subscribe(bus, "jido.hooks.pre", dispatch: {:pid, target: self()})

    {:ok, _after} =
      Bus.subscribe(bus, "jido.hooks.after", dispatch: {:pid, target: self()})

    definition = %CommandDefinition{
      name: "test",
      description: "test",
      hooks: %{pre: false, after: false},
      body: "hello"
    }

    assert {:ok, _result} = CommandRuntime.execute(definition, %{}, %{bus: bus})
    refute_receive {:signal, %Signal{type: "jido.hooks.pre"}}, 250
    refute_receive {:signal, %Signal{type: "jido.hooks.after"}}, 250
  end

  defp unique_bus_name do
    :"jido_command_runtime_bus_#{System.unique_integer([:positive, :monotonic])}"
  end
end
