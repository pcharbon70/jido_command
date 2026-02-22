# Command Declarations

Commands are markdown files with YAML FrontMatter.

## File location

Place command files in either:

- `~/.jido_code/commands/*.md`
- `<cwd>/.jido_code/commands/*.md`

## Minimal command

```markdown
---
name: code-review
description: Review changed files
---
Review {{target_file}} and summarize findings.
```

## Full declaration

```markdown
---
name: code-review
description: Review changed files
model: sonnet
allowed-tools:
  - Read
  - Grep
  - Bash(git diff:*)
jido:
  command_module: Jido.Code.Command.Commands.CodeReview
  hooks:
    pre: true
    after: true
  schema:
    target_file:
      type: string
      required: true
      doc: File path to review
    mode:
      type: atom
      default: standard
---
Review {{target_file}} using mode {{mode}}.
```

## FrontMatter contract

Required top-level keys:

- `name` (non-empty string)
- `description` (non-empty string)

Optional top-level keys:

- `model` (non-empty string)
- `allowed-tools` or `allowed_tools`
- `jido` (map)

Unknown top-level keys are rejected.

## `allowed-tools` / `allowed_tools`

Rules:

- Use only one alias (`allowed-tools` or `allowed_tools`), not both.
- Value can be either a comma-separated string (`"Read, Grep"`) or a list of strings/atoms.
- Empty or blank values are rejected.
- Values are trimmed and de-duplicated.

## `jido` section

Allowed keys under `jido`:

- `command_module`
- `hooks`
- `schema`

### `jido.command_module`

- Optional module name string.
- Must be a valid module path format (for example `Jido.Code.Command.Commands.MyCommand`).
- If omitted, runtime creates a deterministic dynamic module.

### `jido.hooks`

- Optional map with two supported keys only: `pre`, `after`.
- Values must be boolean.
- Defaults: `%{pre: false, after: false}`.

### `jido.schema`

Schema is a map of fields. Each field supports:

- `type` (default `string`)
- `required` (default `false`)
- `doc` (optional string)
- `default` (optional)

Supported `type` values:

- `string`
- `integer`
- `float`
- `boolean`
- `map`
- `atom`
- `list`

Schema rules:

- Field names must match: `^[a-z][a-zA-Z0-9_]*$`
- `required: true` cannot be combined with `default`
- `default` must match declared `type`

## Template interpolation

Runtime interpolates body placeholders from `params`:

- `{{key}}` is replaced by matching param values for that key.

Values are rendered as:

- strings as-is
- atoms via `Atom.to_string/1`
- other values via `inspect/1`
