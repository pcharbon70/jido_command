defmodule JidoCommand.Extensibility.CommandFrontmatterTest do
  use ExUnit.Case, async: true

  alias JidoCommand.Extensibility.CommandFrontmatter

  test "parses command frontmatter with pre and after hooks" do
    markdown = """
    ---
    name: code-review
    description: Review code
    model: sonnet
    allowed-tools: Read, Grep
    jido:
      hooks:
        pre: commands/code_review/pre
        after: commands/code_review/after
    ---
    Body with {{file}}.
    """

    assert {:ok, definition} = CommandFrontmatter.parse_string(markdown, "/tmp/cmd.md")

    assert definition.name == "code-review"
    assert definition.description == "Review code"
    assert definition.model == "sonnet"
    assert definition.allowed_tools == ["Read", "Grep"]
    assert definition.hooks.pre == "commands/code_review/pre"
    assert definition.hooks.after == "commands/code_review/after"
    assert String.contains?(definition.body, "{{file}}")
  end

  test "rejects unknown hook keys" do
    markdown = """
    ---
    name: bad-hooks
    jido:
      hooks:
        before: commands/bad/pre
    ---
    invalid
    """

    assert {:error, {:invalid_hooks, {:unknown_keys, ["before"]}}} =
             CommandFrontmatter.parse_string(markdown, "/tmp/bad.md")
  end
end
