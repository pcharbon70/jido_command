defmodule JidoCommand.Extensibility.CommandDispatcherTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoCommand.Extensibility.CommandDispatcher
  alias JidoCommand.Extensibility.CommandRegistry

  defmodule ProbeExecutor do
    @behaviour JidoCommand.Extensibility.CommandRuntime

    @impl true
    def execute(_definition, _prompt, params, context) do
      test_pid = Map.get(context, :test_pid)
      id = Map.get(params, "id")
      sleep_ms = Map.get(params, "sleep_ms", 200)

      if is_pid(test_pid), do: send(test_pid, {:probe_started, id})
      Process.sleep(sleep_ms)
      {:ok, %{"id" => id}}
    end
  end

  defmodule PermissionsProbeExecutor do
    @behaviour JidoCommand.Extensibility.CommandRuntime

    @impl true
    def execute(_definition, _prompt, _params, context) do
      test_pid = Map.get(context, :test_pid)
      if is_pid(test_pid), do: send(test_pid, {:permissions_seen, Map.get(context, :permissions)})
      {:ok, %{"ok" => true}}
    end
  end

  test "dispatches command.invoke and emits command.completed" do
    %{bus: bus} =
      start_runtime([
        {"hello.md",
         """
         ---
         name: hello
         description: hello command
         ---
         Hi {{user}}
         """}
      ])

    {:ok, _completed_sub} =
      Bus.subscribe(bus, "command.completed", dispatch: {:pid, target: self()})

    {:ok, invoke_signal} =
      Signal.new(
        "command.invoke",
        %{"name" => "hello", "params" => %{"user" => "Pascal"}},
        source: "/test"
      )

    assert {:ok, _} = Bus.publish(bus, [invoke_signal])

    assert_receive {:signal, %Signal{type: "command.completed", data: data}}, 2_000
    assert data["name"] == "hello"
    assert data["result"]["result"]["prompt"] == "Hi Pascal\n"
  end

  test "emits command.failed when invoke payload is missing params" do
    %{bus: bus} = start_runtime()

    {:ok, _failed_sub} =
      Bus.subscribe(bus, "command.failed", dispatch: {:pid, target: self()})

    {:ok, %Signal{id: signal_id} = invoke_signal} =
      Signal.new(
        "command.invoke",
        %{"name" => "hello"},
        source: "/test"
      )

    assert {:ok, _} = Bus.publish(bus, [invoke_signal])

    assert_receive {:signal, %Signal{type: "command.failed", data: data}}, 2_000
    assert data["name"] == "hello"
    assert data["invocation_id"] == signal_id
    assert data["error"] == "invalid command.invoke payload: params is required"
  end

  test "emits command.failed when invocation_id is invalid" do
    %{bus: bus} = start_runtime()

    {:ok, _failed_sub} =
      Bus.subscribe(bus, "command.failed", dispatch: {:pid, target: self()})

    {:ok, %Signal{id: signal_id} = invoke_signal} =
      Signal.new(
        "command.invoke",
        %{"name" => "hello", "params" => %{}, "invocation_id" => 123},
        source: "/test"
      )

    assert {:ok, _} = Bus.publish(bus, [invoke_signal])

    assert_receive {:signal, %Signal{type: "command.failed", data: data}}, 2_000
    assert data["name"] == "hello"
    assert data["invocation_id"] == signal_id

    assert data["error"] ==
             "invalid command.invoke payload: invocation_id must be a non-empty string when provided"
  end

  test "emits command.failed when payload includes unknown keys" do
    %{bus: bus} = start_runtime()

    {:ok, _failed_sub} =
      Bus.subscribe(bus, "command.failed", dispatch: {:pid, target: self()})

    {:ok, %Signal{id: signal_id} = invoke_signal} =
      Signal.new(
        "command.invoke",
        %{"name" => "hello", "params" => %{}, "extra" => true},
        source: "/test"
      )

    assert {:ok, _} = Bus.publish(bus, [invoke_signal])

    assert_receive {:signal, %Signal{type: "command.failed", data: data}}, 2_000
    assert data["name"] == "hello"
    assert data["invocation_id"] == signal_id
    assert data["error"] == "invalid command.invoke payload: unknown keys: extra"
  end

  test "runs invokes concurrently up to max_concurrent limit" do
    %{bus: bus} =
      start_runtime(
        [
          {"probe.md",
           """
           ---
           name: probe
           description: probe command
           ---
           probe
           """}
        ],
        max_concurrent: 2
      )

    assert {:ok, first} =
             Signal.new(
               "command.invoke",
               %{
                 "name" => "probe",
                 "params" => %{"id" => "one", "sleep_ms" => 250},
                 "context" => %{command_executor: ProbeExecutor, test_pid: self()}
               },
               source: "/test"
             )

    assert {:ok, second} =
             Signal.new(
               "command.invoke",
               %{
                 "name" => "probe",
                 "params" => %{"id" => "two", "sleep_ms" => 250},
                 "context" => %{command_executor: ProbeExecutor, test_pid: self()}
               },
               source: "/test"
             )

    assert {:ok, _} = Bus.publish(bus, [first])
    assert {:ok, _} = Bus.publish(bus, [second])

    assert_receive {:probe_started, first_id}, 500
    assert first_id in ["one", "two"]

    assert_receive {:probe_started, second_id}, 150
    assert second_id in ["one", "two"]
    refute second_id == first_id
  end

  test "queues invokes when max_concurrent is reached" do
    %{bus: bus} =
      start_runtime(
        [
          {"probe.md",
           """
           ---
           name: probe
           description: probe command
           ---
           probe
           """}
        ],
        max_concurrent: 1
      )

    assert {:ok, first} =
             Signal.new(
               "command.invoke",
               %{
                 "name" => "probe",
                 "params" => %{"id" => "one", "sleep_ms" => 250},
                 "context" => %{command_executor: ProbeExecutor, test_pid: self()}
               },
               source: "/test"
             )

    assert {:ok, second} =
             Signal.new(
               "command.invoke",
               %{
                 "name" => "probe",
                 "params" => %{"id" => "two", "sleep_ms" => 250},
                 "context" => %{command_executor: ProbeExecutor, test_pid: self()}
               },
               source: "/test"
             )

    assert {:ok, _} = Bus.publish(bus, [first])
    assert {:ok, _} = Bus.publish(bus, [second])

    assert_receive {:probe_started, first_id}, 500
    assert first_id in ["one", "two"]

    refute_receive {:probe_started, _second_id}, 120

    assert_receive {:probe_started, second_id}, 500
    assert second_id in ["one", "two"]
    refute second_id == first_id
  end

  test "injects configured runtime permissions into execution context" do
    runtime_permissions = %{
      allow: ["Read", "Write"],
      deny: ["Bash(rm -rf:*)"],
      ask: ["Bash(npm:*)"]
    }

    %{bus: bus} =
      start_runtime(
        [
          {"probe.md",
           """
           ---
           name: probe
           description: probe command
           ---
           probe
           """}
        ],
        permissions: runtime_permissions
      )

    assert {:ok, invoke_signal} =
             Signal.new(
               "command.invoke",
               %{
                 "name" => "probe",
                 "params" => %{},
                 "context" => %{command_executor: PermissionsProbeExecutor, test_pid: self()}
               },
               source: "/test"
             )

    assert {:ok, _} = Bus.publish(bus, [invoke_signal])
    assert_receive {:permissions_seen, ^runtime_permissions}, 1_000
  end

  test "filters runtime permissions by command allowed-tools before execution" do
    runtime_permissions = %{
      allow: ["Read", "Write", "Bash(git diff:*)"],
      deny: ["Bash(rm -rf:*)", "Bash(git diff:*)"],
      ask: ["Grep", "Read"]
    }

    expected_permissions = %{
      allow: ["Read", "Bash(git diff:*)"],
      deny: ["Bash(git diff:*)"],
      ask: ["Read"]
    }

    %{bus: bus} =
      start_runtime(
        [
          {"probe.md",
           """
           ---
           name: probe
           description: probe command
           allowed-tools:
             - Read
             - Bash(git diff:*)
           ---
           probe
           """}
        ],
        permissions: runtime_permissions
      )

    assert {:ok, invoke_signal} =
             Signal.new(
               "command.invoke",
               %{
                 "name" => "probe",
                 "params" => %{},
                 "context" => %{command_executor: PermissionsProbeExecutor, test_pid: self()}
               },
               source: "/test"
             )

    assert {:ok, _} = Bus.publish(bus, [invoke_signal])
    assert_receive {:permissions_seen, ^expected_permissions}, 1_000
  end

  defp start_runtime(commands \\ [], dispatcher_opts \\ []) do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    File.mkdir_p!(Path.join(global_root, "commands"))
    local_commands_dir = Path.join(local_root, "commands")
    File.mkdir_p!(local_commands_dir)

    Enum.each(commands, fn {filename, markdown} ->
      File.write!(Path.join(local_commands_dir, filename), markdown)
    end)

    bus = unique_bus_name()
    registry = unique_registry_name()
    dispatcher = unique_dispatcher_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    start_supervised!(
      {CommandDispatcher, [name: dispatcher, bus: bus, registry: registry] ++ dispatcher_opts}
    )

    %{bus: bus, registry: registry, dispatcher: dispatcher}
  end

  defp tmp_root do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido_command_dispatcher_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp unique_bus_name do
    :"jido_command_dispatcher_bus_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp unique_registry_name do
    :"jido_command_dispatcher_registry_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp unique_dispatcher_name do
    :"jido_command_dispatcher_#{System.unique_integer([:positive, :monotonic])}"
  end
end
