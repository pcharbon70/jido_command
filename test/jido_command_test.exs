defmodule JidoCommandTest do
  use ExUnit.Case

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoCommand.Extensibility.CommandRegistry

  test "dispatch publishes command.invoke signal" do
    bus = unique_bus_name()
    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.invoke", dispatch: {:pid, target: self()})

    assert {:ok, invocation_id} = JidoCommand.dispatch("demo", %{"x" => 1}, %{}, bus: bus)
    assert is_binary(invocation_id)

    assert_receive {:signal, %Signal{type: "command.invoke", data: data}}, 1_000
    assert data["name"] == "demo"
    assert data["params"] == %{"x" => 1}
    assert data["invocation_id"] == invocation_id
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

    assert ["first"] == JidoCommand.list_commands(registry: registry)

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

    assert :ok = JidoCommand.reload(registry: registry)
    assert ["first", "second"] == JidoCommand.list_commands(registry: registry)
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

    assert [] == JidoCommand.list_commands(registry: registry)
    assert :ok = JidoCommand.register_command(command_path, registry: registry)
    assert ["extra"] == JidoCommand.list_commands(registry: registry)
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

    assert ["review"] == JidoCommand.list_commands(registry: registry)
    assert :ok = JidoCommand.unregister_command("review", registry: registry)
    assert [] == JidoCommand.list_commands(registry: registry)
    assert {:error, :not_found} = JidoCommand.unregister_command("review", registry: registry)
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
