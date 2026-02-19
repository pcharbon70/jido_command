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

  test "dispatch normalizes invalid invocation_id option to a generated id" do
    bus = unique_bus_name()
    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.invoke", dispatch: {:pid, target: self()})

    assert {:ok, invocation_id} =
             JidoCommand.dispatch("demo", %{"x" => 1}, %{}, bus: bus, invocation_id: 123)

    assert is_binary(invocation_id)
    assert invocation_id != ""

    assert_receive {:signal, %Signal{type: "command.invoke", data: data}}, 1_000
    assert data["invocation_id"] == invocation_id
  end

  test "dispatch rejects invalid name, params, and context before publishing" do
    bus = unique_bus_name()
    start_supervised!({Bus, name: bus})

    {:ok, _subscription} =
      Bus.subscribe(bus, "command.invoke", dispatch: {:pid, target: self()})

    assert {:error, :invalid_name} = JidoCommand.dispatch("   ", %{}, %{}, bus: bus)
    assert {:error, :invalid_params} = JidoCommand.dispatch("demo", [], %{}, bus: bus)
    assert {:error, :invalid_context} = JidoCommand.dispatch("demo", %{}, [], bus: bus)

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

  test "register_command rejects blank and non-string paths" do
    assert {:error, :invalid_path} = JidoCommand.register_command("   ")
    assert {:error, :invalid_path} = JidoCommand.register_command(123)
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
             JidoCommand.invoke(
               "review",
               %{},
               %{},
               registry: registry,
               bus: bus,
               permissions: permissions
             )

    assert result["result"]["permissions"] == permissions
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
             JidoCommand.invoke(
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

  test "invoke rejects invalid name, params, and context" do
    assert {:error, :invalid_name} = JidoCommand.invoke("   ", %{}, %{})
    assert {:error, :invalid_params} = JidoCommand.invoke("review", [], %{})
    assert {:error, :invalid_context} = JidoCommand.invoke("review", %{}, [])
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

  test "unregister_command rejects blank and non-string names" do
    assert {:error, :invalid_name} = JidoCommand.unregister_command("   ")
    assert {:error, :invalid_name} = JidoCommand.unregister_command(123)
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
