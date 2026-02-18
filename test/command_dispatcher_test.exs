defmodule JidoCommand.Extensibility.CommandDispatcherTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoCommand.Extensibility.CommandDispatcher
  alias JidoCommand.Extensibility.ExtensionRegistry

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

  defp start_runtime(commands \\ []) do
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
      {ExtensionRegistry,
       name: registry, bus: bus, global_root: global_root, local_root: local_root}
    )

    start_supervised!({CommandDispatcher, name: dispatcher, bus: bus, registry: registry})

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
