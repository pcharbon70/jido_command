defmodule JidoCommand.Extensibility.CommandFrontmatterTest do
  use ExUnit.Case, async: true

  alias JidoCommand.Extensibility.CommandFrontmatter

  test "parses command frontmatter with validated hooks and schema" do
    markdown = """
    ---
    name: code-review
    description: Review code
    model: sonnet
    allowed-tools:
      - Read
      - Grep
    jido:
      command_module: JidoCommand.Commands.CodeReview
      hooks:
        pre: commands/code_review/pre
        after: commands/code_review/after
      schema:
        target_file:
          type: string
          required: true
          doc: File path to review
    ---
    Body with {{target_file}}.
    """

    assert {:ok, definition} = CommandFrontmatter.parse_string(markdown, "/tmp/cmd.md")

    assert definition.name == "code-review"
    assert definition.description == "Review code"
    assert definition.command_module == JidoCommand.Commands.CodeReview
    assert definition.model == "sonnet"
    assert definition.allowed_tools == ["Read", "Grep"]
    assert definition.hooks.pre == "commands/code_review/pre"
    assert definition.hooks.after == "commands/code_review/after"

    assert [target_file: schema_opts] = definition.schema
    assert Keyword.get(schema_opts, :type) == :string
    assert Keyword.get(schema_opts, :required) == true
    assert Keyword.get(schema_opts, :doc) == "File path to review"

    assert String.contains?(definition.body, "{{target_file}}")
  end

  test "rejects unknown hook keys" do
    markdown = """
    ---
    name: bad-hooks
    description: bad
    jido:
      hooks:
        before: commands/bad/pre
    ---
    invalid
    """

    assert {:error, {:invalid_hooks, {:unknown_keys, ["before"]}}} =
             CommandFrontmatter.parse_string(markdown, "/tmp/bad.md")
  end

  test "rejects non-map hook config" do
    markdown = """
    ---
    name: bad-hooks-shape
    description: bad
    jido:
      hooks: true
    ---
    invalid
    """

    assert {:error, {:invalid_hooks, :must_be_map}} =
             CommandFrontmatter.parse_string(markdown, "/tmp/bad_hooks_shape.md")
  end

  test "requires non-empty name and description" do
    missing_name = """
    ---
    description: desc
    ---
    body
    """

    assert {:error, {:invalid_frontmatter_field, "name", :must_be_nonempty_string}} =
             CommandFrontmatter.parse_string(missing_name, "/tmp/missing_name.md")

    missing_description = """
    ---
    name: cmd
    description: ""
    ---
    body
    """

    assert {:error, {:invalid_frontmatter_field, "description", :must_be_nonempty_string}} =
             CommandFrontmatter.parse_string(missing_description, "/tmp/missing_description.md")
  end

  test "rejects invalid hook signal path" do
    markdown = """
    ---
    name: bad-hook-path
    description: bad
    jido:
      hooks:
        pre: "commands bad path"
    ---
    body
    """

    assert {:error, {:invalid_hook_path, "pre", "commands bad path", _reason}} =
             CommandFrontmatter.parse_string(markdown, "/tmp/bad_hook_path.md")
  end

  test "rejects unknown jido keys" do
    markdown = """
    ---
    name: bad-jido
    description: bad
    jido:
      foo: bar
    ---
    body
    """

    assert {:error, {:invalid_jido_keys, ["foo"]}} =
             CommandFrontmatter.parse_string(markdown, "/tmp/bad_jido.md")
  end

  test "rejects unknown schema options and invalid required/default combinations" do
    unknown_schema_option = """
    ---
    name: bad-schema-opt
    description: bad
    jido:
      schema:
        sample:
          type: string
          bogus: true
    ---
    body
    """

    assert {:error, {:invalid_schema_options, "sample", ["bogus"]}} =
             CommandFrontmatter.parse_string(unknown_schema_option, "/tmp/bad_schema_opt.md")

    required_with_default = """
    ---
    name: bad-schema-default
    description: bad
    jido:
      schema:
        sample:
          type: string
          required: true
          default: hello
    ---
    body
    """

    assert {:error, {:invalid_schema_default, "sample", :required_cannot_define_default}} =
             CommandFrontmatter.parse_string(required_with_default, "/tmp/bad_schema_default.md")
  end
end
