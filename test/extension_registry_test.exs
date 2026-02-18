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

  defp tmp_root do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido_command_registry_#{System.unique_integer([:positive, :monotonic])}"
      )

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
