# JidoCommand

JidoCommand is a command-only extensibility runtime built on `jido`, `jido_action`, and `jido_signal`.

It supports:

- Markdown-defined commands (`.md` + YAML FrontMatter)
- Exactly two optional command hook signals (`jido.hooks.pre`, `jido.hooks.after`)
- Signal-bus command dispatch (`command.invoke` -> `command.completed` / `command.failed`)
- `command.invoke` payloads are strictly validated (required/optional keys only)
- API `invoke/dispatch` validate name/params/context input types before execution/publish
- Invalid or blank invocation IDs are normalized to generated non-empty IDs
- Signal-bus registry lifecycle events (`command.registry.reloaded`, `command.registered`, `command.unregistered`, `command.registry.failed`)
- Global + local config roots with local precedence
- Runtime-registered command files are reapplied on `reload`
- Re-registering the same command file path replaces its prior manual command entry
- For duplicate manual command names, the most recent registration wins (including after `reload`)
- Unregistering a manual command restores the next available command for that name immediately

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
    pre: true
    after: true
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

# register one command file at runtime
JidoCommand.register_command("commands/review.md")

# unregister a command by name
JidoCommand.unregister_command("review")
```

## CLI usage

```bash
# list commands
mix run -e 'JidoCommand.CLI.main(["list"])'

# invoke command
mix run -e 'JidoCommand.CLI.main(["invoke", "code-review", "--params", "{\"target_file\":\"lib/foo.ex\"}"])'

# invoke command with explicit invocation id
mix run -e 'JidoCommand.CLI.main(["invoke", "code-review", "--invocation-id", "my-invoke-id"])'

# dispatch command.invoke signal
mix run -e 'JidoCommand.CLI.main(["dispatch", "code-review", "--params", "{\"target_file\":\"lib/foo.ex\"}"])'

# dispatch command.invoke signal with explicit invocation id
mix run -e 'JidoCommand.CLI.main(["dispatch", "code-review", "--invocation-id", "my-dispatch-id"])'

# reload command registry from configured roots
mix run -e 'JidoCommand.CLI.main(["reload"])'

# register one command markdown file at runtime
mix run -e 'JidoCommand.CLI.main(["register-command", "commands/review.md"])'

# unregister one command by name at runtime
mix run -e 'JidoCommand.CLI.main(["unregister-command", "review"])'
```

## Settings

`settings.json` supports these keys in the current implementation:

- `$schema` (optional non-empty string)
- `version` (optional SemVer string)
- `signal_bus.name` (default `:jido_code_bus`)
  Values are normalized to atoms (for example, `"local_bus"` and `":local_bus"` both resolve to `:local_bus`).
- `signal_bus.middleware` (currently supports `Jido.Signal.Bus.Middleware.Logger` with `opts.level`)
- `permissions.allow` (list of capability strings)
- `permissions.deny` (list of capability strings)
- `permissions.ask` (list of capability strings)
- `commands.default_model` (fallback model when a command omits `model`)
- `commands.max_concurrent` (max in-flight command executions in dispatcher)

Unknown top-level settings keys and unknown nested keys under `signal_bus`, `permissions`, and `commands` are rejected at load time.

Dispatcher-managed execution injects normalized permissions into command context as:

```elixir
%{
  permissions: %{
    allow: [...],
    deny: [...],
    ask: [...]
  }
}
```

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
