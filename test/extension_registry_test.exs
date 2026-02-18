defmodule JidoCommand.Extensibility.ExtensionRegistryTest do
  use ExUnit.Case, async: true

  alias JidoCommand.Extensibility.ExtensionRegistry

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
      {ExtensionRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    assert ["greet"] == ExtensionRegistry.list_commands(registry)
    assert {:ok, command_module} = ExtensionRegistry.get_command("greet", registry)

    assert {:ok, result} = Jido.Exec.run(command_module, %{}, %{bus: bus})
    assert String.trim(result["result"]["prompt"]) == "Local greeting"
  end

  test "loads only enabled extensions when allowlist is set" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    extension_manifest_path(global_root, "alpha", "alpha-command", "Alpha extension command")
    extension_manifest_path(global_root, "beta", "beta-command", "Beta extension command")

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Jido.Signal.Bus, name: bus})

    start_supervised!(
      {ExtensionRegistry,
       name: registry,
       bus: bus,
       global_root: global_root,
       local_root: local_root,
       extensions_enabled: ["beta"]}
    )

    assert ["beta-command"] == ExtensionRegistry.list_commands(registry)
    assert {:error, :not_found} = ExtensionRegistry.get_command("alpha-command", registry)
    assert {:ok, _module} = ExtensionRegistry.get_command("beta-command", registry)
  end

  test "skips disabled extensions and denylist wins over allowlist" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    extension_manifest_path(global_root, "alpha", "alpha-command", "Alpha extension command")
    extension_manifest_path(global_root, "beta", "beta-command", "Beta extension command")

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Jido.Signal.Bus, name: bus})

    start_supervised!(
      {ExtensionRegistry,
       name: registry,
       bus: bus,
       global_root: global_root,
       local_root: local_root,
       extensions_enabled: ["alpha", "beta"],
       extensions_disabled: ["beta"]}
    )

    assert ["alpha-command"] == ExtensionRegistry.list_commands(registry)
    assert {:ok, _module} = ExtensionRegistry.get_command("alpha-command", registry)
    assert {:error, :not_found} = ExtensionRegistry.get_command("beta-command", registry)
  end

  test "rejects register_extension for disallowed extension" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    manifest_path =
      extension_manifest_path(global_root, "beta", "beta-command", "Beta extension command")

    bus = unique_bus_name()
    registry = unique_registry_name()

    start_supervised!({Jido.Signal.Bus, name: bus})

    start_supervised!(
      {ExtensionRegistry,
       name: registry,
       bus: bus,
       global_root: global_root,
       local_root: local_root,
       extensions_enabled: ["alpha"]}
    )

    assert {:error, {:extension_not_allowed, "beta"}} =
             ExtensionRegistry.register_extension(manifest_path, registry)

    assert [] == ExtensionRegistry.list_commands(registry)
  end

  defp command_markdown(name, body) do
    """
    ---
    name: #{name}
    description: #{name} description
    jido:
      hooks:
        pre: commands/#{name}/pre
        after: commands/#{name}/after
    ---
    #{body}
    """
  end

  defp extension_manifest_path(root, extension_name, command_name, command_body) do
    extension_root = Path.join([root, "extensions", extension_name])
    commands_dir = Path.join(extension_root, "commands")
    manifest_dir = Path.join(extension_root, ".jido-extension")
    manifest_path = Path.join(manifest_dir, "extension.json")

    File.mkdir_p!(commands_dir)
    File.mkdir_p!(manifest_dir)

    File.write!(
      Path.join(commands_dir, "#{command_name}.md"),
      command_markdown(command_name, command_body)
    )

    File.write!(
      manifest_path,
      Jason.encode!(%{
        "name" => extension_name,
        "version" => "1.0.0",
        "commands" => "./commands"
      })
    )

    manifest_path
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
