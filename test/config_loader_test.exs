defmodule JidoCommand.Config.LoaderTest do
  use ExUnit.Case, async: true

  alias JidoCommand.Config.Loader
  alias JidoCommand.Config.Settings

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
        "signal_bus" => %{"name" => "local_bus"},
        "commands" => %{"max_concurrent" => 10}
      })
    )

    assert {:ok, settings} = Loader.load(global_root: global, local_root: local)
    assert settings.bus_name == :local_bus
    assert settings.commands_default_model == "global-model"
    assert settings.commands_max_concurrent == 10
  end

  test "loads and merges permissions with local precedence" do
    root = tmp_root()
    global = Path.join(root, "global")
    local = Path.join(root, "local")

    File.mkdir_p!(global)
    File.mkdir_p!(local)

    File.write!(
      Path.join(global, "settings.json"),
      Jason.encode!(%{
        "permissions" => %{
          "allow" => ["Read", "Write"],
          "deny" => ["Bash(rm -rf:*)"]
        }
      })
    )

    File.write!(
      Path.join(local, "settings.json"),
      Jason.encode!(%{
        "permissions" => %{
          "deny" => ["Bash(git push:*)"],
          "ask" => ["Bash(npm:*)", " Bash(npm:*) "]
        }
      })
    )

    assert {:ok, settings} = Loader.load(global_root: global, local_root: local)
    assert settings.permissions_allow == ["Read", "Write"]
    assert settings.permissions_deny == ["Bash(git push:*)"]
    assert settings.permissions_ask == ["Bash(npm:*)"]
  end

  test "returns defaults when settings files do not exist" do
    root = tmp_root()
    global = Path.join(root, "missing_global")
    local = Path.join(root, "missing_local")

    assert {:ok, settings} = Loader.load(global_root: global, local_root: local)
    assert settings.bus_name == :jido_code_bus
    assert settings.commands_default_model == nil
    assert settings.commands_max_concurrent == 5
    assert settings.permissions_allow == []
    assert settings.permissions_deny == []
    assert settings.permissions_ask == []
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

  test "returns invalid_settings for unsupported middleware module" do
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

    assert {:error, {:invalid_settings, {:invalid_signal_bus_middleware, 0, :unsupported_module}}} =
             Loader.load(global_root: global, local_root: local)
  end

  test "returns invalid_settings for unknown middleware opts keys" do
    root = tmp_root()
    global = Path.join(root, "global")
    local = Path.join(root, "local")

    File.mkdir_p!(global)
    File.mkdir_p!(local)

    File.write!(
      Path.join(local, "settings.json"),
      Jason.encode!(%{
        "signal_bus" => %{
          "middleware" => [
            %{
              "module" => "Jido.Signal.Bus.Middleware.Logger",
              "opts" => %{"level" => "debug", "format" => "json"}
            }
          ]
        }
      })
    )

    assert {:error,
            {:invalid_settings,
             {:invalid_signal_bus_middleware, 0,
              {:invalid_middleware_opts_keys, {:unknown_keys, ["format"]}}}}} =
             Loader.load(global_root: global, local_root: local)
  end

  test "returns invalid_settings for invalid middleware log levels" do
    root = tmp_root()
    global = Path.join(root, "global")
    local = Path.join(root, "local")

    File.mkdir_p!(global)
    File.mkdir_p!(local)

    File.write!(
      Path.join(local, "settings.json"),
      Jason.encode!(%{
        "signal_bus" => %{
          "middleware" => [
            %{"module" => "Jido.Signal.Bus.Middleware.Logger", "opts" => %{"level" => "trace"}}
          ]
        }
      })
    )

    assert {:error, {:invalid_settings, {:invalid_signal_bus_middleware, 0, :invalid_level}}} =
             Loader.load(global_root: global, local_root: local)
  end

  test "returns invalid_settings for blank signal_bus.name" do
    root = tmp_root()
    global = Path.join(root, "global")
    local = Path.join(root, "local")

    File.mkdir_p!(global)
    File.mkdir_p!(local)

    File.write!(
      Path.join(local, "settings.json"),
      Jason.encode!(%{
        "signal_bus" => %{"name" => "   "}
      })
    )

    assert {:error,
            {:invalid_settings, {:invalid_signal_bus_name, :must_be_nonempty_string_or_atom}}} =
             Loader.load(global_root: global, local_root: local)
  end

  test "returns invalid_settings for unknown top-level settings keys" do
    root = tmp_root()
    global = Path.join(root, "global")
    local = Path.join(root, "local")

    File.mkdir_p!(global)
    File.mkdir_p!(local)

    File.write!(
      Path.join(local, "settings.json"),
      Jason.encode!(%{
        "commands" => %{"max_concurrent" => 5},
        "unknown" => true
      })
    )

    assert {:error, {:invalid_settings, {:invalid_settings_keys, {:unknown_keys, ["unknown"]}}}} =
             Loader.load(global_root: global, local_root: local)
  end

  test "settings validation rejects non-string top-level keys without crashing" do
    settings = %{
      "commands" => %{"max_concurrent" => 5},
      {:unknown, :key} => true
    }

    assert {:error, {:invalid_settings_keys, {:unknown_keys, unknown_keys}}} =
             Settings.validate(settings)

    assert "{:unknown, :key}" in unknown_keys
  end

  test "settings validation rejects conflicting normalized top-level keys" do
    settings = %{
      "commands" => %{"max_concurrent" => 5},
      commands: %{"max_concurrent" => 7}
    }

    assert {:error, {:invalid_settings_keys, {:conflicting_keys, ["commands"]}}} =
             Settings.validate(settings)
  end

  test "returns invalid_settings for unknown nested permissions keys" do
    root = tmp_root()
    global = Path.join(root, "global")
    local = Path.join(root, "local")

    File.mkdir_p!(global)
    File.mkdir_p!(local)

    File.write!(
      Path.join(local, "settings.json"),
      Jason.encode!(%{
        "permissions" => %{
          "allow" => ["Read"],
          "maybe" => ["Write"]
        }
      })
    )

    assert {:error, {:invalid_settings, {:invalid_permissions_keys, {:unknown_keys, ["maybe"]}}}} =
             Loader.load(global_root: global, local_root: local)
  end

  test "settings validation rejects non-string nested keys without crashing" do
    settings = %{
      "permissions" => %{
        "allow" => ["Read"],
        {:maybe, :key} => ["Write"]
      }
    }

    assert {:error, {:invalid_permissions_keys, {:unknown_keys, unknown_keys}}} =
             Settings.validate(settings)

    assert "{:maybe, :key}" in unknown_keys
  end

  test "settings validation rejects conflicting normalized nested keys" do
    settings = %{
      "permissions" => %{
        "allow" => ["Read"],
        allow: ["Write"]
      }
    }

    assert {:error, {:invalid_permissions_keys, {:conflicting_keys, ["allow"]}}} =
             Settings.validate(settings)
  end

  test "settings validation enforces signal_bus.name with atom keys" do
    settings = %{
      signal_bus: %{name: "   "}
    }

    assert {:error, {:invalid_signal_bus_name, :must_be_nonempty_string_or_atom}} =
             Settings.validate(settings)
  end

  test "settings validation enforces commands.max_concurrent with atom keys" do
    settings = %{
      commands: %{max_concurrent: 0}
    }

    assert {:error, {:invalid_max_concurrent, :must_be_positive_integer}} =
             Settings.validate(settings)
  end

  test "settings validation enforces commands.default_model with atom keys" do
    settings = %{
      commands: %{default_model: "   "}
    }

    assert {:error, {:invalid_default_model, :must_be_nonempty_string}} =
             Settings.validate(settings)
  end

  test "settings from_map normalizes atom-key maps" do
    settings =
      Settings.from_map(%{
        signal_bus: %{name: "local_bus"},
        commands: %{default_model: "local-model", max_concurrent: 7},
        permissions: %{allow: ["Read"], ask: "Bash(npm:*)"}
      })

    assert settings.bus_name == :local_bus
    assert settings.commands_default_model == "local-model"
    assert settings.commands_max_concurrent == 7
    assert settings.permissions_allow == ["Read"]
    assert settings.permissions_ask == ["Bash(npm:*)"]
  end

  test "returns invalid_settings for invalid permission item types" do
    root = tmp_root()
    global = Path.join(root, "global")
    local = Path.join(root, "local")

    File.mkdir_p!(global)
    File.mkdir_p!(local)

    File.write!(
      Path.join(local, "settings.json"),
      Jason.encode!(%{
        "permissions" => %{
          "allow" => ["Read", 123]
        }
      })
    )

    assert {:error, {:invalid_settings, {:invalid_permission_item, "allow", 1}}} =
             Loader.load(global_root: global, local_root: local)
  end

  test "returns invalid_settings for invalid commands.max_concurrent values" do
    root = tmp_root()
    global = Path.join(root, "global")
    local = Path.join(root, "local")

    File.mkdir_p!(global)
    File.mkdir_p!(local)

    File.write!(
      Path.join(local, "settings.json"),
      Jason.encode!(%{
        "commands" => %{
          "max_concurrent" => 0
        }
      })
    )

    assert {:error, {:invalid_settings, {:invalid_max_concurrent, :must_be_positive_integer}}} =
             Loader.load(global_root: global, local_root: local)
  end

  test "returns invalid_settings for blank commands.default_model" do
    root = tmp_root()
    global = Path.join(root, "global")
    local = Path.join(root, "local")

    File.mkdir_p!(global)
    File.mkdir_p!(local)

    File.write!(
      Path.join(local, "settings.json"),
      Jason.encode!(%{
        "commands" => %{
          "default_model" => "   "
        }
      })
    )

    assert {:error, {:invalid_settings, {:invalid_default_model, :must_be_nonempty_string}}} =
             Loader.load(global_root: global, local_root: local)
  end

  test "returns invalid_settings for non-string commands.default_model" do
    root = tmp_root()
    global = Path.join(root, "global")
    local = Path.join(root, "local")

    File.mkdir_p!(global)
    File.mkdir_p!(local)

    File.write!(
      Path.join(local, "settings.json"),
      Jason.encode!(%{
        "commands" => %{
          "default_model" => 123
        }
      })
    )

    assert {:error, {:invalid_settings, {:invalid_default_model, :must_be_nonempty_string}}} =
             Loader.load(global_root: global, local_root: local)
  end

  test "returns invalid_settings for invalid $schema value" do
    root = tmp_root()
    global = Path.join(root, "global")
    local = Path.join(root, "local")

    File.mkdir_p!(global)
    File.mkdir_p!(local)

    File.write!(
      Path.join(local, "settings.json"),
      Jason.encode!(%{
        "$schema" => ""
      })
    )

    assert {:error, {:invalid_settings, {:invalid_schema_url, :must_be_nonempty_string}}} =
             Loader.load(global_root: global, local_root: local)
  end

  test "returns invalid_settings for invalid version value" do
    root = tmp_root()
    global = Path.join(root, "global")
    local = Path.join(root, "local")

    File.mkdir_p!(global)
    File.mkdir_p!(local)

    File.write!(
      Path.join(local, "settings.json"),
      Jason.encode!(%{
        "version" => "2"
      })
    )

    assert {:error, {:invalid_settings, {:invalid_version, :must_be_semver}}} =
             Loader.load(global_root: global, local_root: local)
  end

  test "accepts semver version with prerelease metadata" do
    root = tmp_root()
    global = Path.join(root, "global")
    local = Path.join(root, "local")

    File.mkdir_p!(global)
    File.mkdir_p!(local)

    File.write!(
      Path.join(local, "settings.json"),
      Jason.encode!(%{
        "version" => "2.0.0-rc.1+build.5"
      })
    )

    assert {:ok, _settings} = Loader.load(global_root: global, local_root: local)
  end

  test "returns invalid_settings for invalid signal_bus.name type" do
    root = tmp_root()
    global = Path.join(root, "global")
    local = Path.join(root, "local")

    File.mkdir_p!(global)
    File.mkdir_p!(local)

    File.write!(
      Path.join(local, "settings.json"),
      Jason.encode!(%{
        "signal_bus" => %{
          "name" => 123
        }
      })
    )

    assert {:error,
            {:invalid_settings, {:invalid_signal_bus_name, :must_be_nonempty_string_or_atom}}} =
             Loader.load(global_root: global, local_root: local)
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
