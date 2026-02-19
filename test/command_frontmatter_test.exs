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
        pre: true
        after: true
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
    assert definition.hooks.pre == true
    assert definition.hooks.after == true

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
        before: true
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

  test "defaults hook flags to false when hooks config is absent" do
    markdown = """
    ---
    name: no-hooks
    description: no hooks
    ---
    body
    """

    assert {:ok, definition} = CommandFrontmatter.parse_string(markdown, "/tmp/no_hooks.md")
    assert definition.hooks.pre == false
    assert definition.hooks.after == false
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

  test "rejects invalid hook declaration values" do
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

    assert {:error, {:invalid_hook_value, "pre", :must_be_boolean_or_nil}} =
             CommandFrontmatter.parse_string(markdown, "/tmp/bad_hook_value.md")
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

  test "rejects unknown top-level frontmatter keys" do
    markdown = """
    ---
    name: unknown-top-level
    description: bad
    foo: bar
    ---
    body
    """

    assert {:error, {:invalid_frontmatter_keys, {:unknown_keys, ["foo"]}}} =
             CommandFrontmatter.parse_string(markdown, "/tmp/bad_frontmatter_top_keys.md")
  end

  test "supports allowed_tools alias at top-level frontmatter" do
    markdown = """
    ---
    name: alias-tools
    description: alias
    allowed_tools:
      - Read
      - Write
    ---
    body
    """

    assert {:ok, definition} = CommandFrontmatter.parse_string(markdown, "/tmp/alias_tools.md")
    assert definition.allowed_tools == ["Read", "Write"]
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

  test "rejects schema defaults that do not match declared type" do
    markdown = """
    ---
    name: bad-default-type
    description: bad
    jido:
      schema:
        retries:
          type: integer
          default: "three"
    ---
    body
    """

    assert {:error, {:invalid_schema_default_type, "retries", :integer}} =
             CommandFrontmatter.parse_string(markdown, "/tmp/bad_schema_default_type.md")
  end

  test "accepts schema defaults when value matches declared type" do
    markdown = """
    ---
    name: valid-default-types
    description: good
    jido:
      schema:
        str_field:
          type: string
          default: ok
        int_field:
          type: integer
          default: 5
        float_field:
          type: float
          default: 1.5
        bool_field:
          type: boolean
          default: true
        map_field:
          type: map
          default:
            key: value
        list_field:
          type: list
          default:
            - a
            - b
        atom_field:
          type: atom
          default: ready_state
    ---
    body
    """

    assert {:ok, definition} =
             CommandFrontmatter.parse_string(markdown, "/tmp/good_schema_default_type.md")

    schema = Map.new(definition.schema)
    assert Keyword.get(schema.str_field, :default) == "ok"
    assert Keyword.get(schema.int_field, :default) == 5
    assert Keyword.get(schema.float_field, :default) == 1.5
    assert Keyword.get(schema.bool_field, :default) == true
    assert Keyword.get(schema.map_field, :default) == %{"key" => "value"}
    assert Keyword.get(schema.list_field, :default) == ["a", "b"]
    assert Keyword.get(schema.atom_field, :default) == "ready_state"
  end
end
