defmodule JidoCommand.Extensibility.ExtensionManifestTest do
  use ExUnit.Case, async: true

  alias JidoCommand.Extensibility.ExtensionManifest

  test "parses manifest with valid signals schema" do
    path =
      write_manifest(%{
        "name" => "code-quality",
        "version" => "1.0.0",
        "commands" => "./commands",
        "signals" => %{
          "emits" => ["commands/code_review/pre", "command/completed"],
          "subscribes" => ["command/invoke"]
        }
      })

    assert {:ok, manifest} = ExtensionManifest.from_file(path)
    assert manifest.name == "code-quality"
    assert manifest.signals["emits"] == ["commands/code_review/pre", "command/completed"]
    assert manifest.signals["subscribes"] == ["command/invoke"]
  end

  test "rejects non-object signals" do
    path =
      write_manifest(%{
        "name" => "bad-signals",
        "version" => "1.0.0",
        "commands" => "./commands",
        "signals" => []
      })

    assert {:error, {:invalid_manifest, ^path, {:invalid_signals, :must_be_object}}} =
             ExtensionManifest.from_file(path)
  end

  test "rejects unknown signal keys" do
    path =
      write_manifest(%{
        "name" => "bad-signals",
        "version" => "1.0.0",
        "commands" => "./commands",
        "signals" => %{"before" => ["commands/review/pre"]}
      })

    assert {:error, {:invalid_manifest, ^path, {:invalid_signals, {:unknown_keys, ["before"]}}}} =
             ExtensionManifest.from_file(path)
  end

  test "rejects invalid signal list entry type" do
    path =
      write_manifest(%{
        "name" => "bad-signals",
        "version" => "1.0.0",
        "commands" => "./commands",
        "signals" => %{"emits" => [123], "subscribes" => []}
      })

    assert {:error, {:invalid_manifest, ^path, {:invalid_signals, {"emits", :must_be_string}}}} =
             ExtensionManifest.from_file(path)
  end

  test "rejects invalid signal path value" do
    path =
      write_manifest(%{
        "name" => "bad-signals",
        "version" => "1.0.0",
        "commands" => "./commands",
        "signals" => %{"emits" => ["commands bad path"], "subscribes" => []}
      })

    assert {:error,
            {:invalid_manifest, ^path,
             {:invalid_signals, {"emits", "commands bad path", _reason}}}} =
             ExtensionManifest.from_file(path)
  end

  test "rejects missing required fields" do
    path =
      write_manifest(%{
        "name" => "missing-commands",
        "version" => "1.0.0"
      })

    assert {:error, {:missing_or_invalid_field, "commands"}} =
             ExtensionManifest.from_file(path)
  end

  defp write_manifest(map) do
    root =
      Path.join(
        System.tmp_dir!(),
        "jido_command_manifest_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    path = Path.join(root, "extension.json")
    File.write!(path, Jason.encode!(map))
    path
  end
end
