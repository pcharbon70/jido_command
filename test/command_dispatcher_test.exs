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

  defmodule ContextProbeExecutor do
    @behaviour JidoCommand.Extensibility.CommandRuntime

    @impl true
    def execute(_definition, _prompt, _params, context) do
      test_pid = Map.get(context, :test_pid)
      if is_pid(test_pid), do: send(test_pid, {:context_seen, context})
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

  test "emits command.failed when registry server is unavailable" do
    bus = unique_bus_name()
    registry = unique_registry_name()
    dispatcher = unique_dispatcher_name()

    start_supervised!({Bus, name: bus})
    start_supervised!({CommandDispatcher, name: dispatcher, bus: bus, registry: registry})

    {:ok, _failed_sub} =
      Bus.subscribe(bus, "command.failed", dispatch: {:pid, target: self()})

    {:ok, %Signal{id: signal_id} = invoke_signal} =
      Signal.new(
        "command.invoke",
        %{"name" => "hello", "params" => %{}},
        source: "/test"
      )

    assert {:ok, _} = Bus.publish(bus, [invoke_signal])

    assert_receive {:signal, %Signal{type: "command.failed", data: data}}, 2_000
    assert data["name"] == "hello"
    assert data["invocation_id"] == signal_id
    assert String.starts_with?(data["error"], "registry unavailable:")
    assert String.contains?(data["error"], "registry_unavailable")
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

  test "emits command.failed when payload includes non-string unknown keys" do
    %{bus: bus, dispatcher: dispatcher} = start_runtime()

    {:ok, _failed_sub} =
      Bus.subscribe(bus, "command.failed", dispatch: {:pid, target: self()})

    send(
      dispatcher,
      {:signal,
       %Signal{
         type: "command.invoke",
         id: "sig-nonstring-key",
         source: "/test",
         data: %{"name" => "hello", "params" => %{}, {:extra, :key} => true}
       }}
    )

    assert_receive {:signal, %Signal{type: "command.failed", data: data}}, 2_000
    assert data["name"] == "hello"
    assert data["invocation_id"] == "sig-nonstring-key"
    assert String.starts_with?(data["error"], "invalid command.invoke payload: unknown keys:")
    assert String.contains?(data["error"], "{:extra, :key}")
  end

  test "emits command.failed when payload includes conflicting normalized keys" do
    %{bus: bus, dispatcher: dispatcher} = start_runtime()

    {:ok, _failed_sub} =
      Bus.subscribe(bus, "command.failed", dispatch: {:pid, target: self()})

    send(
      dispatcher,
      {:signal,
       %Signal{
         type: "command.invoke",
         id: "sig-conflicting-name",
         source: "/test",
         data: %{"name" => "hello", :name => "shadow", "params" => %{}}
       }}
    )

    assert_receive {:signal, %Signal{type: "command.failed", data: data}}, 2_000
    assert data["name"] == "hello"
    assert data["invocation_id"] == "sig-conflicting-name"
    assert data["error"] == "invalid command.invoke payload: conflicting keys: name"
  end

  test "emits command.failed when payload includes conflicting invocation_id keys" do
    %{bus: bus, dispatcher: dispatcher} = start_runtime()

    {:ok, _failed_sub} =
      Bus.subscribe(bus, "command.failed", dispatch: {:pid, target: self()})

    send(
      dispatcher,
      {:signal,
       %Signal{
         type: "command.invoke",
         id: "sig-conflicting-id",
         source: "/test",
         data: %{
           "name" => "hello",
           "params" => %{},
           "invocation_id" => "primary-id",
           :invocation_id => "shadow-id"
         }
       }}
    )

    assert_receive {:signal, %Signal{type: "command.failed", data: data}}, 2_000
    assert data["name"] == "hello"
    assert data["invocation_id"] == "primary-id"
    assert data["error"] == "invalid command.invoke payload: conflicting keys: invocation_id"
  end

  test "emits command.failed when params includes nested conflicting normalized keys" do
    %{bus: bus, dispatcher: dispatcher} = start_runtime()

    {:ok, _failed_sub} =
      Bus.subscribe(bus, "command.failed", dispatch: {:pid, target: self()})

    send(
      dispatcher,
      {:signal,
       %Signal{
         type: "command.invoke",
         id: "sig-conflicting-params",
         source: "/test",
         data: %{
           "name" => "hello",
           "params" => %{"meta" => %{"x" => 1, :x => 2}}
         }
       }}
    )

    assert_receive {:signal, %Signal{type: "command.failed", data: data}}, 2_000
    assert data["name"] == "hello"
    assert data["invocation_id"] == "sig-conflicting-params"

    assert data["error"] ==
             "invalid command.invoke payload: params contains conflicting keys: x"
  end

  test "emits command.failed when context includes nested conflicting normalized keys" do
    %{bus: bus, dispatcher: dispatcher} = start_runtime()

    {:ok, _failed_sub} =
      Bus.subscribe(bus, "command.failed", dispatch: {:pid, target: self()})

    send(
      dispatcher,
      {:signal,
       %Signal{
         type: "command.invoke",
         id: "sig-conflicting-context",
         source: "/test",
         data: %{
           "name" => "hello",
           "params" => %{},
           "context" => %{"permissions" => %{"allow" => ["Read"], :allow => ["Write"]}},
           "invocation_id" => "request-id"
         }
       }}
    )

    assert_receive {:signal, %Signal{type: "command.failed", data: data}}, 2_000
    assert data["name"] == "hello"
    assert data["invocation_id"] == "request-id"

    assert data["error"] ==
             "invalid command.invoke payload: context contains conflicting keys: allow"
  end

  test "normalizes dispatcher-managed context keys before command execution" do
    %{bus: bus} =
      start_runtime([
        {"probe.md",
         """
         ---
         name: probe
         description: probe command
         ---
         probe
         """}
      ])

    {:ok, _completed_sub} =
      Bus.subscribe(bus, "command.completed", dispatch: {:pid, target: self()})

    {:ok, %Signal{id: signal_id} = invoke_signal} =
      Signal.new(
        "command.invoke",
        %{
          "name" => "probe",
          "params" => %{},
          "context" => %{
            "bus" => :ignored_bus,
            "invocation_id" => "ignored-id",
            "permissions" => %{"allow" => ["Read"]},
            test_pid: self(),
            command_executor: ContextProbeExecutor
          }
        },
        source: "/test"
      )

    assert {:ok, _} = Bus.publish(bus, [invoke_signal])

    assert_receive {:context_seen, runtime_context}, 2_000
    assert runtime_context[:bus] == bus
    assert runtime_context[:invocation_id] == signal_id
    assert runtime_context[:permissions] == %{allow: [], deny: [], ask: []}
    refute Map.has_key?(runtime_context, "bus")
    refute Map.has_key?(runtime_context, "invocation_id")
    refute Map.has_key?(runtime_context, "permissions")

    assert_receive {:signal, %Signal{type: "command.completed", data: data}}, 2_000
    assert data["name"] == "probe"
    assert data["invocation_id"] == signal_id
  end

  test "emits command.failed with generated invocation_id when non-map payload has no signal id" do
    %{bus: bus, dispatcher: dispatcher} = start_runtime()

    {:ok, _failed_sub} =
      Bus.subscribe(bus, "command.failed", dispatch: {:pid, target: self()})

    send(
      dispatcher,
      {:signal, %Signal{type: "command.invoke", id: nil, source: "/test", data: "invalid"}}
    )

    assert_receive {:signal, %Signal{type: "command.failed", data: data}}, 2_000
    assert data["name"] == "<invalid>"
    assert is_binary(data["invocation_id"])
    assert data["invocation_id"] != ""
    assert data["error"] == "invalid command.invoke payload: data must be an object"
  end

  test "emits command.failed with generated fallback invocation_id when payload id is missing" do
    %{bus: bus, dispatcher: dispatcher} = start_runtime()

    {:ok, _failed_sub} =
      Bus.subscribe(bus, "command.failed", dispatch: {:pid, target: self()})

    send(
      dispatcher,
      {:signal,
       %Signal{type: "command.invoke", id: nil, source: "/test", data: %{"name" => "hello"}}}
    )

    assert_receive {:signal, %Signal{type: "command.failed", data: data}}, 2_000
    assert data["name"] == "hello"
    assert is_binary(data["invocation_id"])
    assert data["invocation_id"] != ""
    assert data["error"] == "invalid command.invoke payload: params is required"
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
      ask: ["Grep", "Read", "Bash(git diff:*)"]
    }

    expected_permissions = %{
      allow: ["Read", "Bash(git diff:--stat)"],
      deny: ["Bash(git diff:--stat)"],
      ask: ["Read", "Bash(git diff:--stat)"]
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
             - Bash(git diff:--stat)
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

  test "keeps exact runtime permissions when command allowed-tools uses wildcard" do
    runtime_permissions = %{
      allow: ["Bash(git diff:--stat)", "Read"],
      deny: ["Bash(git diff:--name-only)", "Write"],
      ask: ["Bash(git diff:--cached)", "Grep"]
    }

    expected_permissions = %{
      allow: ["Bash(git diff:--stat)"],
      deny: ["Bash(git diff:--name-only)"],
      ask: ["Bash(git diff:--cached)"]
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

  test "does not match wildcard runtime permissions across command token boundaries" do
    runtime_permissions = %{
      allow: ["Bash(git:*)"],
      deny: ["Bash(git:*)"],
      ask: ["Bash(git:*)"]
    }

    expected_permissions = %{allow: [], deny: [], ask: []}

    %{bus: bus} =
      start_runtime(
        [
          {"probe.md",
           """
           ---
           name: probe
           description: probe command
           allowed-tools:
             - Bash(git diff:--stat)
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
