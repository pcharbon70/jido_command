defmodule JidoCommand.Extensibility.CommandDispatcherTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoCommand.Extensibility.CommandDispatcher
  alias JidoCommand.Extensibility.ExtensionRegistry

  test "dispatches command.invoke and emits command.completed" do
    root = tmp_root()
    global_root = Path.join(root, "global")
    local_root = Path.join(root, "local")

    File.mkdir_p!(Path.join(global_root, "commands"))
    File.mkdir_p!(Path.join(local_root, "commands"))

    File.write!(
      Path.join(local_root, "commands/hello.md"),
      """
      ---
      name: hello
      description: hello command
      ---
      Hi {{user}}
      """
    )

    bus = unique_bus_name()
    registry = unique_registry_name()
    dispatcher = unique_dispatcher_name()

    start_supervised!({Bus, name: bus})

    start_supervised!(
      {ExtensionRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    start_supervised!({CommandDispatcher, name: dispatcher, bus: bus, registry: registry})

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

  defp tmp_root do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido_command_dispatcher_#{System.unique_integer([:positive, :monotonic])}"
      )

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
