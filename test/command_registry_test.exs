defmodule JidoCommand.Extensibility.CommandRegistryTest do
  use ExUnit.Case, async: true

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

    start_supervised!({Jido.Signal.Bus, name: bus})

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

    start_supervised!({Jido.Signal.Bus, name: bus})

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

    start_supervised!({Jido.Signal.Bus, name: bus})

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

    start_supervised!({Jido.Signal.Bus, name: bus})

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

    start_supervised!({Jido.Signal.Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert [] == CommandRegistry.list_commands(registry)
    assert :ok = CommandRegistry.register_command(manual_file, registry)
    assert ["manual"] == CommandRegistry.list_commands(registry)

    assert {:ok, entry} = CommandRegistry.get_command_entry("manual", registry)
    assert entry.meta[:scope] == :manual
  end

  test "register_command returns error for missing file" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(Path.join(local_root, "commands"))

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Jido.Signal.Bus, name: bus})

    start_supervised!(
      {CommandRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    missing_file = Path.join(root, "manual/missing.md")

    assert {:error, {:command_file_not_found, missing_path}} =
             CommandRegistry.register_command(missing_file, registry)

    assert missing_path == Path.expand(missing_file)
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
