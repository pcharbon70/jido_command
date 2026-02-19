defmodule JidoCommand.Extensibility.CommandCompilerTest do
  use ExUnit.Case, async: true

  alias JidoCommand.Extensibility.Command

  test "uses jido.command_module when provided" do
    unique = System.unique_integer([:positive, :monotonic])
    module_name = "JidoCommand.TestDynamic.Command#{unique}"
    module_atom = Module.concat([module_name])

    file = Path.join(System.tmp_dir!(), "command_compiler_#{unique}.md")

    File.write!(
      file,
      """
      ---
      name: explicit-module
      description: Explicit module command
      jido:
        command_module: #{module_name}
      ---
      Hello {{name}}
      """
    )

    assert {:ok, compiled} = Command.from_markdown(file)
    assert compiled.module == module_atom

    assert {:ok, result} = Jido.Exec.run(compiled.module, %{"name" => "Pascal"}, %{})
    assert result["result"]["prompt"] == "Hello Pascal\n"
  end

  test "normalizes atom schema defaults so compiled commands run with implicit defaults" do
    unique = System.unique_integer([:positive, :monotonic])
    file = Path.join(System.tmp_dir!(), "command_compiler_atom_default_#{unique}.md")

    File.write!(
      file,
      """
      ---
      name: atom-default
      description: Atom default command
      jido:
        schema:
          status:
            type: atom
            default: ready_state
      ---
      Status {{status}}
      """
    )

    assert {:ok, compiled} = Command.from_markdown(file)
    assert {:ok, result} = Jido.Exec.run(compiled.module, %{}, %{})
    assert result["result"]["prompt"] == "Status ready_state\n"

    params = result["result"]["params"]
    status = Map.get(params, :status) || Map.get(params, "status")

    assert status == :ready_state
  end
end
