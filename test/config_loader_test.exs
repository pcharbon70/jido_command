defmodule JidoCommand.Config.LoaderTest do
  use ExUnit.Case, async: true

  alias JidoCommand.Config.Loader

  test "loads and merges global and local settings with local precedence" do
    root = tmp_root()
    global = Path.join(root, "global")
    local = Path.join(root, "local")

    File.mkdir_p!(global)
    File.mkdir_p!(local)

    File.write!(
      Path.join(global, "settings.json"),
      Jason.encode!(%{
        "signal_bus" => %{"name" => ":global_bus"},
        "commands" => %{"max_concurrent" => 2, "default_model" => "global-model"}
      })
    )

    File.write!(
      Path.join(local, "settings.json"),
      Jason.encode!(%{
        "signal_bus" => %{"name" => ":local_bus"},
        "commands" => %{"max_concurrent" => 10}
      })
    )

    assert {:ok, settings} = Loader.load(global_root: global, local_root: local)
    assert settings.bus_name == "local_bus"
    assert settings.commands_default_model == "global-model"
    assert settings.commands_max_concurrent == 10
  end

  test "returns defaults when settings files do not exist" do
    root = tmp_root()
    global = Path.join(root, "missing_global")
    local = Path.join(root, "missing_local")

    assert {:ok, settings} = Loader.load(global_root: global, local_root: local)
    assert settings.bus_name == :jido_code_bus
    assert settings.commands_default_model == nil
    assert settings.commands_max_concurrent == 5
  end

  test "returns invalid_json error for malformed settings file" do
    root = tmp_root()
    global = Path.join(root, "global")
    local = Path.join(root, "local")

    File.mkdir_p!(global)
    File.mkdir_p!(local)
    File.write!(Path.join(global, "settings.json"), "{not valid json")

    assert {:error, {:invalid_json, path, _reason}} =
             Loader.load(global_root: global, local_root: local)

    assert path == Path.join(global, "settings.json")
  end

  test "falls back to default middleware when configured middleware is unsupported" do
    root = tmp_root()
    global = Path.join(root, "global")
    local = Path.join(root, "local")

    File.mkdir_p!(global)
    File.mkdir_p!(local)

    File.write!(
      Path.join(local, "settings.json"),
      Jason.encode!(%{
        "signal_bus" => %{
          "name" => ":bus_for_middleware_test",
          "middleware" => [
            %{"module" => "Unknown.Middleware", "opts" => %{"level" => "debug"}}
          ]
        }
      })
    )

    assert {:ok, settings} = Loader.load(global_root: global, local_root: local)
    assert settings.bus_middleware == [{Jido.Signal.Bus.Middleware.Logger, level: :debug}]
  end

  defp tmp_root do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido_command_loader_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end
end
