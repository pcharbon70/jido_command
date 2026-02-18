# JidoCommand

JidoCommand is a command-only extensibility runtime built on `jido`, `jido_action`, and `jido_signal`.

It supports:

- Markdown-defined commands (`.md` + YAML FrontMatter)
- Exactly two optional command hook signals (`jido.hooks.pre`, `jido.hooks.after`)
- Signal-bus command dispatch (`command.invoke` -> `command.completed` / `command.failed`)
- Global + local config roots with local precedence

## Runtime layout

- Global root: `~/.jido_code`
- Local root: `<cwd>/.jido_code`

Loaded directories:

- `commands/*.md`

## FrontMatter example

```yaml
---
name: code-review
description: Review changed files
allowed-tools: Read, Grep
jido:
  hooks:
    pre: commands.code_review.pre
    after: commands.code_review.after
---
Review {{target_file}} and summarize findings.
```

## API usage

```elixir
# direct invoke
JidoCommand.invoke("code-review", %{"target_file" => "lib/foo.ex"})

# signal-based dispatch
JidoCommand.dispatch("code-review", %{"target_file" => "lib/foo.ex"})

# list currently loaded commands
JidoCommand.list_commands()

# reload command registry from disk
JidoCommand.reload()
```

## CLI usage

```bash
# list commands
mix run -e 'JidoCommand.CLI.main(["list"])'

# invoke command
mix run -e 'JidoCommand.CLI.main(["invoke", "code-review", "--params", "{\"target_file\":\"lib/foo.ex\"}"])'

# dispatch command.invoke signal
mix run -e 'JidoCommand.CLI.main(["dispatch", "code-review", "--params", "{\"target_file\":\"lib/foo.ex\"}"])'

# reload command registry from configured roots
mix run -e 'JidoCommand.CLI.main(["reload"])'
```

## Settings

`settings.json` supports these keys in the current implementation:

- `signal_bus.name` (default `:jido_code_bus`)
- `signal_bus.middleware` (supports logger middleware level)
- `commands.default_model` (fallback model when a command omits `model`)
- `commands.max_concurrent` (max in-flight command executions in dispatcher)

## Contracts

Signal contracts are documented in:

- `/Users/Pascal/code/jido/jido_command/docs/architecture/contracts.md`

## Development

```bash
mix deps.get
mix test
```

## Pre-commit Hook

This repo ships a managed Git hook at `.githooks/pre-commit` that blocks commits unless all checks pass:

- `mix test`
- `mix credo --strict`
- `mix dialyzer`

Enable it locally with:

```bash
git config core.hooksPath .githooks
```
