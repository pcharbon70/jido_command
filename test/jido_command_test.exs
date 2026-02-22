defmodule Jido.Code.CommandTest do
  use ExUnit.Case

  alias Jido.Code.Command, as: Command
  alias Jido.Code.Command.Extensibility.CommandRegistry
  alias Jido.Signal
  alias Jido.Signal.Bus

  test "dispatch publishes command.invoke signal" do
    bus = unique_bus_name()
    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.invoke", dispatch: {:pid, target: self()})

    assert {:ok, invocation_id} = Command.dispatch("demo", %{"x" => 1}, %{}, bus: bus)
    assert is_binary(invocation_id)

    assert_receive {:signal, %Signal{type: "command.invoke", data: data}}, 1_000
    assert data["name"] == "demo"
    assert data["params"] == %{"x" => 1}
    assert data["invocation_id"] == invocation_id
  end

  test "dispatch normalizes invalid invocation_id option to a generated id" do
    bus = unique_bus_name()
    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.invoke", dispatch: {:pid, target: self()})

    assert {:ok, invocation_id} =
             Command.dispatch("demo", %{"x" => 1}, %{}, bus: bus, invocation_id: 123)

    assert is_binary(invocation_id)
    assert invocation_id != ""

    assert_receive {:signal, %Signal{type: "command.invoke", data: data}}, 1_000
    assert data["invocation_id"] == invocation_id
  end

  test "dispatch uses string-key context invocation_id when options invocation_id is absent" do
    bus = unique_bus_name()
    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.invoke", dispatch: {:pid, target: self()})

    assert {:ok, invocation_id} =
             Command.dispatch("demo", %{"x" => 1}, %{"invocation_id" => "context-id"},
               bus: bus
             )

    assert invocation_id == "context-id"

    assert_receive {:signal, %Signal{type: "command.invoke", data: data}}, 1_000
    assert data["invocation_id"] == "context-id"
  end

  test "dispatch rejects conflicting context invocation_id key forms" do
    bus = unique_bus_name()
    start_supervised!({Bus, name: bus})

    assert {:error, :conflicting_context_invocation_id_keys} =
             Command.dispatch(
               "demo",
               %{"x" => 1},
               %{"invocation_id" => "b", invocation_id: "a"},
               bus: bus
             )
  end

  test "dispatch options invocation_id overrides context invocation_id" do
    bus = unique_bus_name()
    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.invoke", dispatch: {:pid, target: self()})

    assert {:ok, invocation_id} =
             Command.dispatch("demo", %{"x" => 1}, %{"invocation_id" => "context-id"},
               bus: bus,
               invocation_id: "options-id"
             )

    assert invocation_id == "options-id"

    assert_receive {:signal, %Signal{type: "command.invoke", data: data}}, 1_000
    assert data["invocation_id"] == "options-id"
  end

  test "dispatch falls back to context invocation_id when options invocation_id is invalid" do
    bus = unique_bus_name()
    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.invoke", dispatch: {:pid, target: self()})

    assert {:ok, invocation_id} =
             Command.dispatch("demo", %{"x" => 1}, %{"invocation_id" => "context-id"},
               bus: bus,
               invocation_id: 123
             )

    assert invocation_id == "context-id"

    assert_receive {:signal, %Signal{type: "command.invoke", data: data}}, 1_000
    assert data["invocation_id"] == "context-id"
  end

  test "dispatch rejects invalid name, params, and context before publishing" do
    bus = unique_bus_name()
    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.invoke", dispatch: {:pid, target: self()})

    assert {:error, :invalid_name} = Command.dispatch("   ", %{}, %{}, bus: bus)
    assert {:error, :invalid_params} = Command.dispatch("demo", [], %{}, bus: bus)
    assert {:error, :invalid_context} = Command.dispatch("demo", %{}, [], bus: bus)

    refute_receive {:signal, %Signal{type: "command.invoke"}}, 250
  end

  test "dispatch rejects invalid and unknown options before publishing" do
    bus = unique_bus_name()
    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.invoke", dispatch: {:pid, target: self()})

    assert {:error, :invalid_dispatch_options} =
             Command.dispatch("demo", %{}, %{}, %{bus: bus})

    assert {:error, {:invalid_dispatch_options_keys, ["permissions"]}} =
             Command.dispatch("demo", %{}, %{}, bus: bus, permissions: %{"allow" => ["Read"]})

    refute_receive {:signal, %Signal{type: "command.invoke"}}, 250
  end

  test "dispatch rejects invalid bus option values before publishing" do
    assert {:error, :invalid_bus} = Command.dispatch("demo", %{}, %{}, bus: 123)
    assert {:error, :invalid_bus} = Command.dispatch("demo", %{}, %{}, bus: "")
    assert {:error, :invalid_bus} = Command.dispatch("demo", %{}, %{}, bus: "   ")
    assert {:error, :invalid_bus} = Command.dispatch("demo", %{}, %{}, bus: ":")
    assert {:error, :invalid_bus} = Command.dispatch("demo", %{}, %{}, bus: {nil, :registry})
    assert {:error, :invalid_bus} = Command.dispatch("demo", %{}, %{}, bus: {:demo, nil})
    assert {:error, :invalid_bus} = Command.dispatch("demo", %{}, %{}, bus: {:demo, :global})
    assert {:error, :invalid_bus} = Command.dispatch("demo", %{}, %{}, bus: {:global, :demo})
  end

  test "dispatch uses string-key context bus when options bus is absent" do
    context_bus = unique_bus_name()
    start_supervised!({Bus, name: context_bus})

    {:ok, _subscription} =
      Bus.subscribe(context_bus, "command.invoke", dispatch: {:pid, target: self()})

    context_bus_name = ":" <> Atom.to_string(context_bus)

    assert {:ok, invocation_id} =
             Command.dispatch("demo", %{"x" => 1}, %{"bus" => context_bus_name})

    assert_receive {:signal, %Signal{type: "command.invoke", data: data}}, 1_000
    assert data["name"] == "demo"
    assert data["params"] == %{"x" => 1}
    assert data["invocation_id"] == invocation_id
  end

  test "dispatch accepts colon-prefixed bus option string" do
    option_bus = unique_bus_name()
    option_bus_name = ":" <> Atom.to_string(option_bus)
    start_supervised!({Bus, name: option_bus})

    {:ok, _subscription} =
      Bus.subscribe(option_bus, "command.invoke", dispatch: {:pid, target: self()})

    assert {:ok, invocation_id} =
             Command.dispatch("demo", %{"x" => 1}, %{}, bus: option_bus_name)

    assert_receive {:signal, %Signal{type: "command.invoke", data: data}}, 1_000
    assert data["name"] == "demo"
    assert data["params"] == %{"x" => 1}
    assert data["invocation_id"] == invocation_id
  end

  test "dispatch options bus overrides context bus" do
    option_bus = unique_bus_name()
    context_bus = unique_bus_name()
    start_supervised!({Bus, name: option_bus})
    start_supervised!({Bus, name: context_bus})

    {:ok, _subscription} =
      Bus.subscribe(option_bus, "command.invoke", dispatch: {:pid, target: self()})

    assert {:ok, invocation_id} =
             Command.dispatch(
               "demo",
               %{"x" => 1},
               %{"bus" => context_bus},
               bus: option_bus
             )

    assert_receive {:signal, %Signal{type: "command.invoke", data: data}}, 1_000
    assert data["name"] == "demo"
    assert data["params"] == %{"x" => 1}
    assert data["invocation_id"] == invocation_id
  end

  test "dispatch rejects invalid context bus values before publishing" do
    assert {:error, :invalid_context_bus} = Command.dispatch("demo", %{}, %{"bus" => 123})
    assert {:error, :invalid_context_bus} = Command.dispatch("demo", %{}, %{"bus" => ""})
    assert {:error, :invalid_context_bus} = Command.dispatch("demo", %{}, %{bus: "   "})
    assert {:error, :invalid_context_bus} = Command.dispatch("demo", %{}, %{"bus" => ":"})

    assert {:error, :invalid_context_bus} =
             Command.dispatch("demo", %{}, %{bus: {nil, :registry}})

    assert {:error, :invalid_context_bus} =
             Command.dispatch("demo", %{}, %{"bus" => {:demo, nil}})

    assert {:error, :invalid_context_bus} =
             Command.dispatch("demo", %{}, %{bus: {:demo, :global}})

    assert {:error, :invalid_context_bus} =
             Command.dispatch("demo", %{}, %{"bus" => {:global, :demo}})
  end

  test "dispatch rejects conflicting option keys before publishing" do
    bus = unique_bus_name()
    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.invoke", dispatch: {:pid, target: self()})

    assert {:error, {:invalid_dispatch_options_conflicting_keys, ["bus"]}} =
             Command.dispatch("demo", %{}, %{}, bus: bus, bus: :other_bus)

    refute_receive {:signal, %Signal{type: "command.invoke"}}, 250
  end

  test "dispatch returns normalized bus_unavailable error when bus is not running" do
    bus = unique_bus_name()

    assert {:error, {:bus_unavailable, :noproc}} =
             Command.dispatch("demo", %{}, %{}, bus: bus)
  end

  test "dispatch normalizes publish argument errors for unknown tuple registry bus target" do
    missing_registry =
      :"jido_command_missing_registry_#{System.unique_integer([:positive, :monotonic])}"

    assert {:error, {:bus_unavailable, :invalid_bus_target}} =
             Command.dispatch("demo", %{}, %{}, bus: {:demo, missing_registry})
  end

  test "dispatch rejects conflicting normalized keys in params and context before publishing" do
    bus = unique_bus_name()
    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.invoke", dispatch: {:pid, target: self()})

    assert {:error, {:invalid_params_conflicting_keys, ["x"]}} =
             Command.dispatch("demo", %{"meta" => %{"x" => 1, :x => 2}}, %{}, bus: bus)

    assert {:error, {:invalid_context_conflicting_keys, ["allow"]}} =
             Command.dispatch(
               "demo",
               %{},
               %{"permissions" => %{"allow" => ["Read"], :allow => ["Write"]}},
               bus: bus
             )

    refute_receive {:signal, %Signal{type: "command.invoke"}}, 250
  end

  test "reload refreshes registry command index" do
    root = tmp_root("reload")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_commands_dir = Path.join(local_root, "commands")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(local_commands_dir)

    File.write!(
      Path.join(local_commands_dir, "first.md"),
      """
      ---
      name: first
      description: first command
      ---
      first
      """
    )

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert ["first"] == Command.list_commands(registry: registry)

    File.write!(
      Path.join(local_commands_dir, "second.md"),
      """
      ---
      name: second
      description: second command
      ---
      second
      """
    )

    assert :ok = Command.reload(registry: registry)
    assert ["first", "second"] == Command.list_commands(registry: registry)
  end

  test "reload rejects invalid, unknown, and conflicting options" do
    assert {:error, :invalid_reload_options} =
             Command.reload(%{registry: CommandRegistry})

    assert {:error, {:invalid_reload_options_keys, ["bus"]}} =
             Command.reload(bus: :jido_code_bus)

    assert {:error, {:invalid_reload_options_conflicting_keys, ["registry"]}} =
             Command.reload(registry: :first, registry: :second)
  end

  test "reload rejects invalid registry option values" do
    assert {:error, :invalid_registry} = Command.reload(registry: 123)
  end

  test "reload returns error when registry server is unavailable" do
    registry = unique_registry_name()
    assert {:error, {:registry_unavailable, :noproc}} = Command.reload(registry: registry)
  end

  test "list_commands rejects invalid, unknown, and conflicting options" do
    assert {:error, :invalid_list_commands_options} =
             Command.list_commands(%{registry: CommandRegistry})

    assert {:error, {:invalid_list_commands_options_keys, ["bus"]}} =
             Command.list_commands(bus: :jido_code_bus)

    assert {:error, {:invalid_list_commands_options_conflicting_keys, ["registry"]}} =
             Command.list_commands(registry: :first, registry: :second)
  end

  test "list_commands rejects invalid registry option values" do
    assert {:error, :invalid_registry} = Command.list_commands(registry: 123)
  end

  test "list_commands returns error when registry server is unavailable" do
    registry = unique_registry_name()

    assert {:error, {:registry_unavailable, :noproc}} =
             Command.list_commands(registry: registry)
  end

  test "register_command loads a command into registry" do
    root = tmp_root("register")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    manual_dir = Path.join(root, "manual")
    command_path = Path.join(manual_dir, "extra.md")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(Path.join(local_root, "commands"))
    File.mkdir_p!(manual_dir)

    File.write!(
      command_path,
      """
      ---
      name: extra
      description: extra command
      ---
      extra
      """
    )

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert [] == Command.list_commands(registry: registry)
    assert :ok = Command.register_command(command_path, registry: registry)
    assert ["extra"] == Command.list_commands(registry: registry)
  end

  test "register_command rejects blank and non-string paths" do
    assert {:error, :invalid_path} = Command.register_command("   ")
    assert {:error, :invalid_path} = Command.register_command(123)
  end

  test "register_command rejects invalid, unknown, and conflicting options" do
    assert {:error, :invalid_register_command_options} =
             Command.register_command("command.md", %{registry: CommandRegistry})

    assert {:error, {:invalid_register_command_options_keys, ["bus"]}} =
             Command.register_command("command.md", bus: :jido_code_bus)

    assert {:error, {:invalid_register_command_options_conflicting_keys, ["registry"]}} =
             Command.register_command("command.md", registry: :first, registry: :second)
  end

  test "register_command rejects invalid registry option values" do
    assert {:error, :invalid_registry} =
             Command.register_command("command.md", registry: 123)
  end

  test "register_command returns error when registry server is unavailable" do
    registry = unique_registry_name()

    assert {:error, {:registry_unavailable, :noproc}} =
             Command.register_command("command.md", registry: registry)
  end

  test "invoke applies permissions from options into execution context" do
    root = tmp_root("invoke_permissions")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_commands_dir = Path.join(local_root, "commands")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(local_commands_dir)

    File.write!(
      Path.join(local_commands_dir, "review.md"),
      """
      ---
      name: review
      description: review command
      ---
      review
      """
    )

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    permissions = %{
      allow: ["Read"],
      deny: ["Bash(rm -rf:*)"],
      ask: ["Bash(npm:*)"]
    }

    assert {:ok, result} =
             Command.invoke(
               "review",
               %{},
               %{},
               registry: registry,
               bus: bus,
               permissions: permissions
             )

    assert result["result"]["permissions"] == permissions
  end

  test "invoke applies allowed-tools filtering to permissions from options" do
    root = tmp_root("invoke_allowed_tools_filter")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_commands_dir = Path.join(local_root, "commands")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(local_commands_dir)

    File.write!(
      Path.join(local_commands_dir, "review.md"),
      """
      ---
      name: review
      description: review command
      allowed-tools:
        - Bash(git diff:--stat)
      ---
      review
      """
    )

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    permissions = %{
      allow: ["Bash(git diff:*)"],
      deny: ["Bash(git diff:*)"],
      ask: ["Bash(git diff:*)"]
    }

    expected_permissions = %{
      allow: ["Bash(git diff:--stat)"],
      deny: ["Bash(git diff:--stat)"],
      ask: ["Bash(git diff:--stat)"]
    }

    assert {:ok, result} =
             Command.invoke(
               "review",
               %{},
               %{},
               registry: registry,
               bus: bus,
               permissions: permissions
             )

    assert result["result"]["permissions"] == expected_permissions
  end

  test "invoke preserves exact matching permissions when allowed-tools uses wildcard" do
    root = tmp_root("invoke_allowed_tools_wildcard")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_commands_dir = Path.join(local_root, "commands")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(local_commands_dir)

    File.write!(
      Path.join(local_commands_dir, "review.md"),
      """
      ---
      name: review
      description: review command
      allowed-tools:
        - Bash(git diff:*)
      ---
      review
      """
    )

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    permissions = %{
      allow: ["Bash(git diff:--stat)", "Read"],
      deny: ["Bash(git diff:--name-only)", "Write"],
      ask: ["Bash(git diff:--cached)", "Grep"]
    }

    expected_permissions = %{
      allow: ["Bash(git diff:--stat)"],
      deny: ["Bash(git diff:--name-only)"],
      ask: ["Bash(git diff:--cached)"]
    }

    assert {:ok, result} =
             Command.invoke(
               "review",
               %{},
               %{},
               registry: registry,
               bus: bus,
               permissions: permissions
             )

    assert result["result"]["permissions"] == expected_permissions
  end

  test "invoke uses context permissions when options permissions are absent" do
    root = tmp_root("invoke_context_permissions")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_commands_dir = Path.join(local_root, "commands")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(local_commands_dir)

    File.write!(
      Path.join(local_commands_dir, "review.md"),
      """
      ---
      name: review
      description: review command
      allowed-tools:
        - Bash(git diff:--stat)
      ---
      review
      """
    )

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    context = %{
      "permissions" => %{
        "allow" => ["Bash(git diff:*)"],
        "deny" => ["Bash(git diff:*)"],
        "ask" => ["Bash(git diff:*)"]
      }
    }

    expected_permissions = %{
      allow: ["Bash(git diff:--stat)"],
      deny: ["Bash(git diff:--stat)"],
      ask: ["Bash(git diff:--stat)"]
    }

    assert {:ok, result} =
             Command.invoke("review", %{}, context, registry: registry, bus: bus)

    assert result["result"]["permissions"] == expected_permissions
  end

  test "invoke options permissions override context permissions" do
    root = tmp_root("invoke_permissions_override")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_commands_dir = Path.join(local_root, "commands")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(local_commands_dir)

    File.write!(
      Path.join(local_commands_dir, "review.md"),
      """
      ---
      name: review
      description: review command
      allowed-tools:
        - Bash(git diff:*)
      ---
      review
      """
    )

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    context = %{
      "permissions" => %{
        "allow" => ["Read"],
        "deny" => ["Write"],
        "ask" => ["Grep"]
      }
    }

    options_permissions = %{
      allow: ["Bash(git diff:--stat)", "Read"],
      deny: ["Bash(git diff:--name-only)", "Write"],
      ask: ["Bash(git diff:--cached)", "Grep"]
    }

    expected_permissions = %{
      allow: ["Bash(git diff:--stat)"],
      deny: ["Bash(git diff:--name-only)"],
      ask: ["Bash(git diff:--cached)"]
    }

    assert {:ok, result} =
             Command.invoke(
               "review",
               %{},
               context,
               registry: registry,
               bus: bus,
               permissions: options_permissions
             )

    assert result["result"]["permissions"] == expected_permissions
  end

  test "invoke normalizes invalid invocation_id in options and context" do
    root = tmp_root("invoke_invocation_id")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_commands_dir = Path.join(local_root, "commands")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(local_commands_dir)

    File.write!(
      Path.join(local_commands_dir, "review.md"),
      """
      ---
      name: review
      description: review command
      ---
      review
      """
    )

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert {:ok, result} =
             Command.invoke(
               "review",
               %{},
               %{invocation_id: 123},
               registry: registry,
               bus: bus,
               invocation_id: ""
             )

    invocation_id = result["invocation_id"]
    assert is_binary(invocation_id)
    assert invocation_id != ""
  end

  test "invoke uses string-key context invocation_id when options invocation_id is absent" do
    root = tmp_root("invoke_context_string_invocation_id")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_commands_dir = Path.join(local_root, "commands")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(local_commands_dir)

    File.write!(
      Path.join(local_commands_dir, "review.md"),
      """
      ---
      name: review
      description: review command
      ---
      review
      """
    )

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert {:ok, result} =
             Command.invoke(
               "review",
               %{},
               %{"invocation_id" => "context-id"},
               registry: registry,
               bus: bus
             )

    assert result["invocation_id"] == "context-id"
  end

  test "invoke rejects conflicting context invocation_id key forms" do
    assert {:error, :conflicting_context_invocation_id_keys} =
             Command.invoke("review", %{}, %{"invocation_id" => "b", invocation_id: "a"})
  end

  test "invoke options invocation_id overrides context invocation_id" do
    root = tmp_root("invoke_options_invocation_id_override")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_commands_dir = Path.join(local_root, "commands")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(local_commands_dir)

    File.write!(
      Path.join(local_commands_dir, "review.md"),
      """
      ---
      name: review
      description: review command
      ---
      review
      """
    )

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert {:ok, result} =
             Command.invoke(
               "review",
               %{},
               %{"invocation_id" => "context-id"},
               registry: registry,
               bus: bus,
               invocation_id: "options-id"
             )

    assert result["invocation_id"] == "options-id"
  end

  test "invoke falls back to context invocation_id when options invocation_id is invalid" do
    root = tmp_root("invoke_options_invocation_id_invalid_fallback")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_commands_dir = Path.join(local_root, "commands")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(local_commands_dir)

    File.write!(
      Path.join(local_commands_dir, "review.md"),
      """
      ---
      name: review
      description: review command
      ---
      review
      """
    )

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert {:ok, result} =
             Command.invoke(
               "review",
               %{},
               %{"invocation_id" => "context-id"},
               registry: registry,
               bus: bus,
               invocation_id: 123
             )

    assert result["invocation_id"] == "context-id"
  end

  test "invoke uses string-key context bus when options bus is absent" do
    root = tmp_root("invoke_context_string_bus")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_commands_dir = Path.join(local_root, "commands")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(local_commands_dir)

    File.write!(
      Path.join(local_commands_dir, "review.md"),
      """
      ---
      name: review
      description: review command
      jido:
        hooks:
          pre: true
      ---
      review
      """
    )

    context_bus = unique_bus_name()
    registry_bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: context_bus})
    start_supervised!({Bus, name: registry_bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: registry_bus, global_root: global_root, local_root: local_root}
    )

    {:ok, _subscription} =
      Bus.subscribe(context_bus, "jido.hooks.pre", dispatch: {:pid, target: self()})

    context_bus_name = ":" <> Atom.to_string(context_bus)

    assert {:ok, _result} =
             Command.invoke(
               "review",
               %{},
               %{"bus" => context_bus_name},
               registry: registry
             )

    assert_receive {:signal, %Signal{type: "jido.hooks.pre", data: data}}, 1_000
    assert data["command"] == "review"
  end

  test "invoke options bus overrides context bus" do
    root = tmp_root("invoke_options_bus_override")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_commands_dir = Path.join(local_root, "commands")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(local_commands_dir)

    File.write!(
      Path.join(local_commands_dir, "review.md"),
      """
      ---
      name: review
      description: review command
      jido:
        hooks:
          pre: true
      ---
      review
      """
    )

    option_bus = unique_bus_name()
    context_bus = unique_bus_name()
    registry_bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: option_bus})
    start_supervised!({Bus, name: context_bus})
    start_supervised!({Bus, name: registry_bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: registry_bus, global_root: global_root, local_root: local_root}
    )

    {:ok, _subscription} =
      Bus.subscribe(option_bus, "jido.hooks.pre", dispatch: {:pid, target: self()})

    option_bus_name = ":" <> Atom.to_string(option_bus)

    assert {:ok, _result} =
             Command.invoke(
               "review",
               %{},
               %{bus: context_bus},
               registry: registry,
               bus: option_bus_name
             )

    assert_receive {:signal, %Signal{type: "jido.hooks.pre", data: data}}, 1_000
    assert data["command"] == "review"
  end

  test "invoke rejects invalid name, params, and context" do
    assert {:error, :invalid_name} = Command.invoke("   ", %{}, %{})
    assert {:error, :invalid_params} = Command.invoke("review", [], %{})
    assert {:error, :invalid_context} = Command.invoke("review", %{}, [])
  end

  test "invoke rejects invalid and unknown options" do
    assert {:error, :invalid_invoke_options} =
             Command.invoke("review", %{}, %{}, %{registry: CommandRegistry})

    assert {:error, {:invalid_invoke_options_keys, ["permission"]}} =
             Command.invoke("review", %{}, %{}, permission: %{"allow" => ["Read"]})
  end

  test "invoke rejects invalid bus option values" do
    assert {:error, :invalid_bus} = Command.invoke("review", %{}, %{}, bus: 123)
    assert {:error, :invalid_bus} = Command.invoke("review", %{}, %{}, bus: "")
    assert {:error, :invalid_bus} = Command.invoke("review", %{}, %{}, bus: "   ")
    assert {:error, :invalid_bus} = Command.invoke("review", %{}, %{}, bus: ":")
    assert {:error, :invalid_bus} = Command.invoke("review", %{}, %{}, bus: {nil, :registry})
    assert {:error, :invalid_bus} = Command.invoke("review", %{}, %{}, bus: {:demo, nil})
    assert {:error, :invalid_bus} = Command.invoke("review", %{}, %{}, bus: {:demo, :global})
    assert {:error, :invalid_bus} = Command.invoke("review", %{}, %{}, bus: {:global, :demo})
  end

  test "invoke rejects invalid context bus values" do
    assert {:error, :invalid_context_bus} = Command.invoke("review", %{}, %{"bus" => 123})
    assert {:error, :invalid_context_bus} = Command.invoke("review", %{}, %{bus: ""})
    assert {:error, :invalid_context_bus} = Command.invoke("review", %{}, %{"bus" => "   "})
    assert {:error, :invalid_context_bus} = Command.invoke("review", %{}, %{"bus" => ":"})

    assert {:error, :invalid_context_bus} =
             Command.invoke("review", %{}, %{bus: {nil, :registry}})

    assert {:error, :invalid_context_bus} =
             Command.invoke("review", %{}, %{"bus" => {:demo, nil}})

    assert {:error, :invalid_context_bus} =
             Command.invoke("review", %{}, %{bus: {:demo, :global}})

    assert {:error, :invalid_context_bus} =
             Command.invoke("review", %{}, %{"bus" => {:global, :demo}})
  end

  test "invoke rejects conflicting option keys" do
    assert {:error, {:invalid_invoke_options_conflicting_keys, ["bus"]}} =
             Command.invoke("review", %{}, %{}, bus: :first, bus: :second)
  end

  test "invoke rejects invalid registry option values" do
    assert {:error, :invalid_registry} =
             Command.invoke("review", %{}, %{}, registry: 123)
  end

  test "invoke returns error when registry server is unavailable" do
    registry = unique_registry_name()

    assert {:error, {:registry_unavailable, :noproc}} =
             Command.invoke("review", %{}, %{}, registry: registry)
  end

  test "invoke rejects conflicting normalized keys in params and context" do
    assert {:error, {:invalid_params_conflicting_keys, ["x"]}} =
             Command.invoke("review", %{"meta" => %{"x" => 1, :x => 2}}, %{})

    assert {:error, {:invalid_context_conflicting_keys, ["allow"]}} =
             Command.invoke(
               "review",
               %{},
               %{"permissions" => %{"allow" => ["Read"], :allow => ["Write"]}}
             )
  end

  test "invoke rejects conflicting normalized keys in permissions options" do
    assert {:error, {:invalid_permissions_conflicting_keys, ["allow"]}} =
             Command.invoke(
               "review",
               %{},
               %{},
               permissions: %{"allow" => ["Read"], allow: ["Write"]}
             )
  end

  test "invoke rejects non-map permissions option values" do
    assert {:error, :invalid_permissions} =
             Command.invoke("review", %{}, %{}, permissions: "Read")

    assert {:error, :invalid_permissions} =
             Command.invoke("review", %{}, %{}, permissions: ["Read"])
  end

  test "invoke rejects unknown permissions option keys" do
    assert {:error, {:invalid_permissions_keys, ["extra"]}} =
             Command.invoke("review", %{}, %{},
               permissions: %{"allow" => ["Read"], "extra" => true}
             )
  end

  test "invoke rejects non-string unknown permissions option keys" do
    assert {:error, {:invalid_permissions_keys, unknown_keys}} =
             Command.invoke("review", %{}, %{},
               permissions: %{{:extra, :key} => true, allow: ["Read"]}
             )

    assert "{:extra, :key}" in unknown_keys
  end

  test "invoke rejects non-list permissions option bucket values" do
    assert {:error, {:invalid_permissions_value, "allow", :must_be_list}} =
             Command.invoke("review", %{}, %{}, permissions: %{"allow" => "Read"})

    assert {:error, {:invalid_permissions_value, "allow", :must_be_list}} =
             Command.invoke("review", %{}, %{}, permissions: %{"allow" => false})

    assert {:error, {:invalid_permissions_value, "allow", :must_be_list}} =
             Command.invoke("review", %{}, %{}, permissions: %{allow: false})
  end

  test "invoke rejects non-string permissions option list items" do
    assert {:error, {:invalid_permissions_item, "ask", 1}} =
             Command.invoke("review", %{}, %{}, permissions: %{"ask" => ["Read", 123]})
  end

  test "invoke rejects non-map context permissions value" do
    assert {:error, :invalid_context_permissions} =
             Command.invoke("review", %{}, %{"permissions" => "Read"})
  end

  test "invoke rejects unknown context permissions keys" do
    assert {:error, {:invalid_context_permissions_keys, ["extra"]}} =
             Command.invoke("review", %{}, %{
               "permissions" => %{"allow" => ["Read"], "extra" => true}
             })
  end

  test "invoke rejects invalid context permissions bucket values and items" do
    assert {:error, {:invalid_context_permissions_value, "allow", :must_be_list}} =
             Command.invoke("review", %{}, %{"permissions" => %{"allow" => "Read"}})

    assert {:error, {:invalid_context_permissions_value, "deny", :must_be_list}} =
             Command.invoke("review", %{}, %{"permissions" => %{"deny" => false}})

    assert {:error, {:invalid_context_permissions_item, "ask", 1}} =
             Command.invoke("review", %{}, %{"permissions" => %{"ask" => ["Read", 123]}})
  end

  test "unregister_command removes a command from registry" do
    root = tmp_root("unregister")
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_commands_dir = Path.join(local_root, "commands")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(local_commands_dir)

    File.write!(
      Path.join(local_commands_dir, "review.md"),
      """
      ---
      name: review
      description: review command
      ---
      review
      """
    )

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert ["review"] == Command.list_commands(registry: registry)
    assert :ok = Command.unregister_command("review", registry: registry)
    assert [] == Command.list_commands(registry: registry)
    assert {:error, :not_found} = Command.unregister_command("review", registry: registry)
  end

  test "unregister_command rejects blank and non-string names" do
    assert {:error, :invalid_name} = Command.unregister_command("   ")
    assert {:error, :invalid_name} = Command.unregister_command(123)
  end

  test "unregister_command rejects invalid, unknown, and conflicting options" do
    assert {:error, :invalid_unregister_command_options} =
             Command.unregister_command("review", %{registry: CommandRegistry})

    assert {:error, {:invalid_unregister_command_options_keys, ["bus"]}} =
             Command.unregister_command("review", bus: :jido_code_bus)

    assert {:error, {:invalid_unregister_command_options_conflicting_keys, ["registry"]}} =
             Command.unregister_command("review", registry: :first, registry: :second)
  end

  test "unregister_command rejects invalid registry option values" do
    assert {:error, :invalid_registry} =
             Command.unregister_command("review", registry: 123)
  end

  test "unregister_command returns error when registry server is unavailable" do
    registry = unique_registry_name()

    assert {:error, {:registry_unavailable, :noproc}} =
             Command.unregister_command("review", registry: registry)
  end

  defp unique_bus_name do
    :"jido_command_test_bus_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp unique_registry_name do
    :"jido_command_test_registry_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp tmp_root(suffix) do
    root =
      Path.join(
        System.tmp_dir!(),
        "jido_command_test_#{suffix}_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end
end
