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

  defmodule RaisingExecutor do
    @behaviour JidoCommand.Extensibility.CommandRuntime

    @impl true
    def execute(_definition, _prompt, _params, _context), do: raise("boom")
  end

  defmodule InvalidResponseExecutor do
    @behaviour JidoCommand.Extensibility.CommandRuntime

    @impl true
    def execute(_definition, _prompt, _params, _context), do: :ok
  end

  defmodule ContextProbeExecutor do
    @behaviour JidoCommand.Extensibility.CommandRuntime

    @impl true
    def execute(_definition, _prompt, _params, context) do
      test_pid = Map.get(context, :test_pid)
      if is_pid(test_pid), do: send(test_pid, {:context_seen, context})
      {:ok, %{"ok" => true}}
    end
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

  test "normalizes invalid invocation_id values for runtime result and hooks" do
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
      body: "hello"
    }

    assert {:ok, result} =
             CommandRuntime.execute(definition, %{}, %{bus: bus, invocation_id: 123})

    invocation_id = result["invocation_id"]
    assert is_binary(invocation_id)
    assert invocation_id != ""

    assert_receive {:signal, %Signal{type: "jido.hooks.pre", data: pre_data}}, 1_000
    assert pre_data["invocation_id"] == invocation_id

    assert_receive {:signal, %Signal{type: "jido.hooks.after", data: after_data}}, 1_000
    assert after_data["invocation_id"] == invocation_id
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

  test "emits after hook when executor raises" do
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

    assert {:error, {:executor_exception, %RuntimeError{message: "boom"}, _stacktrace}} =
             CommandRuntime.execute(definition, %{}, %{
               bus: bus,
               command_executor: RaisingExecutor
             })

    assert_receive {:signal, %Signal{type: "jido.hooks.after", data: after_data}}, 1_000
    assert after_data["status"] == "error"
  end

  test "returns executor error when response shape is invalid" do
    definition = %CommandDefinition{
      name: "test",
      description: "test",
      hooks: %{pre: false, after: false},
      body: "ignored"
    }

    assert {:error, {:invalid_executor_response, :ok}} =
             CommandRuntime.execute(definition, %{}, %{command_executor: InvalidResponseExecutor})
  end

  test "applies command allowed_tools as top-level permissions filter" do
    definition = %CommandDefinition{
      name: "test",
      description: "test",
      hooks: %{pre: false, after: false},
      allowed_tools: ["Read", "Bash(git diff:--stat)"],
      body: "ignored"
    }

    context = %{
      command_executor: ContextProbeExecutor,
      test_pid: self(),
      permissions: %{
        allow: ["Read", "Write", "Bash(git diff:*)"],
        deny: ["Bash(rm -rf:*)", "Bash(git diff:*)"],
        ask: ["Grep", "Read", "Bash(git diff:*)"]
      }
    }

    assert {:ok, _result} = CommandRuntime.execute(definition, %{}, context)

    assert_receive {:context_seen, seen_context}, 1_000
    assert seen_context.allowed_tools == ["Read", "Bash(git diff:--stat)"]

    assert seen_context.permissions == %{
             allow: ["Read", "Bash(git diff:--stat)"],
             deny: ["Bash(git diff:--stat)"],
             ask: ["Read", "Bash(git diff:--stat)"]
           }
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
