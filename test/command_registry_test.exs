defmodule JidoCommand.Extensibility.CommandRegistryTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoCommand.Extensibility.CommandRegistry

  test "loads global and local commands with local override" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(Path.join(local_root, "commands"))

    File.write!(
      Path.join(global_root, "commands/greet.md"),
      command_markdown("greet", "Global greeting")
    )

    File.write!(
      Path.join(local_root, "commands/greet.md"),
      command_markdown("greet", "Local greeting")
    )

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert ["greet"] == CommandRegistry.list_commands(registry)
    assert {:ok, command_module} = CommandRegistry.get_command("greet", registry)

    assert {:ok, result} = Jido.Exec.run(command_module, %{}, %{bus: bus})
    assert String.trim(result["result"]["prompt"]) == "Local greeting"
  end

  test "applies default model when command model is unset" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    File.mkdir_p!(Path.join(local_root, "commands"))

    File.write!(
      Path.join(local_root, "commands/analyze.md"),
      command_markdown("analyze", "Analyze this code")
    )

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry,
       bus: bus,
       global_root: global_root,
       local_root: local_root,
       default_model: "gpt-5"}
    )

    assert {:ok, command_module} = CommandRegistry.get_command("analyze", registry)
    assert {:ok, result} = Jido.Exec.run(command_module, %{}, %{bus: bus})
    assert result["result"]["model"] == "gpt-5"
  end

  test "keeps command-specific model over default model" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    File.mkdir_p!(Path.join(local_root, "commands"))

    File.write!(
      Path.join(local_root, "commands/review.md"),
      """
      ---
      name: review
      description: review description
      model: sonnet
      ---
      Review code
      """
    )

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry,
       bus: bus,
       global_root: global_root,
       local_root: local_root,
       default_model: "gpt-5"}
    )

    assert {:ok, command_module} = CommandRegistry.get_command("review", registry)
    assert {:ok, result} = Jido.Exec.run(command_module, %{}, %{bus: bus})
    assert result["result"]["model"] == "sonnet"
  end

  test "reload updates command index" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_commands = Path.join(local_root, "commands")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(local_commands)

    File.write!(
      Path.join(local_commands, "first.md"),
      command_markdown("first", "first")
    )

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.registry.reloaded", dispatch: {:pid, target: self()})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert ["first"] == CommandRegistry.list_commands(registry)

    File.write!(
      Path.join(local_commands, "second.md"),
      command_markdown("second", "second")
    )

    assert :ok = CommandRegistry.reload(registry)
    assert ["first", "second"] == CommandRegistry.list_commands(registry)

    assert_receive {:signal, %Signal{type: "command.registry.reloaded", data: data}}, 1_000
    assert data["previous_count"] == 1
    assert data["current_count"] == 2
  end

  test "register_command adds command from file path" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    manual_dir = Path.join(root, "manual")
    manual_file = Path.join(manual_dir, "manual.md")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(Path.join(local_root, "commands"))
    File.mkdir_p!(manual_dir)

    File.write!(manual_file, command_markdown("manual", "Manual command"))

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.registered", dispatch: {:pid, target: self()})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert [] == CommandRegistry.list_commands(registry)
    assert :ok = CommandRegistry.register_command(manual_file, registry)
    assert ["manual"] == CommandRegistry.list_commands(registry)

    assert {:ok, entry} = CommandRegistry.get_command_entry("manual", registry)
    assert entry.meta[:scope] == :manual

    assert_receive {:signal, %Signal{type: "command.registered", data: data}}, 1_000
    assert data["name"] == "manual"
    assert data["path"] == Path.expand(manual_file)
    assert data["scope"] == "manual"
    assert data["current_count"] == 1
  end

  test "reload keeps manually registered commands" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    manual_dir = Path.join(root, "manual")
    manual_file = Path.join(manual_dir, "manual.md")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(Path.join(local_root, "commands"))
    File.mkdir_p!(manual_dir)

    File.write!(manual_file, command_markdown("manual", "Manual command"))

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert :ok = CommandRegistry.register_command(manual_file, registry)
    assert ["manual"] == CommandRegistry.list_commands(registry)

    assert :ok = CommandRegistry.reload(registry)
    assert ["manual"] == CommandRegistry.list_commands(registry)
  end

  test "unregistered manual command stays removed after reload" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    manual_dir = Path.join(root, "manual")
    manual_file = Path.join(manual_dir, "manual.md")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(Path.join(local_root, "commands"))
    File.mkdir_p!(manual_dir)

    File.write!(manual_file, command_markdown("manual", "Manual command"))

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert :ok = CommandRegistry.register_command(manual_file, registry)
    assert ["manual"] == CommandRegistry.list_commands(registry)

    assert :ok = CommandRegistry.unregister_command("manual", registry)
    assert [] == CommandRegistry.list_commands(registry)

    assert :ok = CommandRegistry.reload(registry)
    assert [] == CommandRegistry.list_commands(registry)
  end

  test "register_command on same path replaces prior manual command name" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    manual_dir = Path.join(root, "manual")
    manual_file = Path.join(manual_dir, "manual.md")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(Path.join(local_root, "commands"))
    File.mkdir_p!(manual_dir)

    File.write!(manual_file, command_markdown("manual-old", "Manual command old"))

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert :ok = CommandRegistry.register_command(manual_file, registry)
    assert ["manual-old"] == CommandRegistry.list_commands(registry)

    File.write!(manual_file, command_markdown("manual-new", "Manual command new"))

    assert :ok = CommandRegistry.register_command(manual_file, registry)
    assert ["manual-new"] == CommandRegistry.list_commands(registry)
    assert {:error, :not_found} = CommandRegistry.get_command("manual-old", registry)
    assert {:ok, _module} = CommandRegistry.get_command("manual-new", registry)
  end

  test "register_command returns error for missing file" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(Path.join(local_root, "commands"))

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.registry.failed", dispatch: {:pid, target: self()})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    missing_file = Path.join(root, "manual/missing.md")

    assert {:error, {:command_file_not_found, missing_path}} =
             CommandRegistry.register_command(missing_file, registry)

    assert missing_path == Path.expand(missing_file)

    assert_receive {:signal, %Signal{type: "command.registry.failed", data: data}}, 1_000
    assert data["operation"] == "register"
    assert data["path"] == Path.expand(missing_file)
    assert String.contains?(data["error"], "command_file_not_found")
  end

  test "unregister_command removes an existing command" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(Path.join(local_root, "commands"))

    File.write!(
      Path.join(local_root, "commands/review.md"),
      command_markdown("review", "Review command")
    )

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.unregistered", dispatch: {:pid, target: self()})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert ["review"] == CommandRegistry.list_commands(registry)
    assert :ok = CommandRegistry.unregister_command("review", registry)
    assert [] == CommandRegistry.list_commands(registry)
    assert {:error, :not_found} = CommandRegistry.get_command("review", registry)

    assert_receive {:signal, %Signal{type: "command.unregistered", data: data}}, 1_000
    assert data["name"] == "review"
    assert data["current_count"] == 0
  end

  test "unregister_command returns not_found for unknown command" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(Path.join(local_root, "commands"))

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.registry.failed", dispatch: {:pid, target: self()})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert {:error, :not_found} = CommandRegistry.unregister_command("missing", registry)

    assert_receive {:signal, %Signal{type: "command.registry.failed", data: data}}, 1_000
    assert data["operation"] == "unregister"
    assert data["name"] == "missing"
    assert data["error"] == "not_found"
  end

  test "unregister_command returns invalid_name for blank command name" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(Path.join(local_root, "commands"))

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.registry.failed", dispatch: {:pid, target: self()})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert {:error, :invalid_name} = CommandRegistry.unregister_command("   ", registry)

    assert_receive {:signal, %Signal{type: "command.registry.failed", data: data}}, 1_000
    assert data["operation"] == "unregister"
    assert data["name"] == "   "
    assert data["error"] == "invalid_name"
  end

  test "reload failure emits command.registry.failed and preserves current registry state" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")
    local_commands = Path.join(local_root, "commands")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(local_commands)

    valid_path = Path.join(local_commands, "valid.md")
    File.write!(valid_path, command_markdown("valid", "ok"))

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.registry.failed", dispatch: {:pid, target: self()})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert ["valid"] == CommandRegistry.list_commands(registry)

    File.write!(
      valid_path,
      """
      ---
      name: valid
      ---
      invalid
      """
    )

    assert {:error, {:load_commands_failed, :local, ^local_commands, _reason}} =
             CommandRegistry.reload(registry)

    assert ["valid"] == CommandRegistry.list_commands(registry)

    assert_receive {:signal, %Signal{type: "command.registry.failed", data: data}}, 1_000
    assert data["operation"] == "reload"
    assert data["previous_count"] == 1
    assert data["current_count"] == 1
    assert String.contains?(data["error"], "load_commands_failed")
  end

  defp command_markdown(name, body) do
    """
    ---
    name: #{name}
    description: #{name} description
    ---
    #{body}
    """
  end

  defp tmp_root do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido_command_registry_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp unique_bus_name do
    :"jido_command_registry_bus_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp unique_registry_name do
    :"jido_command_registry_#{System.unique_integer([:positive, :monotonic])}"
  end
end
