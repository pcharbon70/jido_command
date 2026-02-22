# User Guides

These guides explain how to use `jido_command` as it exists today: a command-only runtime built on the Jido signal bus.

## What this runtime does

- Loads markdown commands from global and local roots.
- Compiles each command into a `Jido.Action` module.
- Executes commands directly (`invoke`) or by publishing `command.invoke` signals (`dispatch`).
- Emits optional command hook signals (`jido.hooks.pre`, `jido.hooks.after`).

## Guides

- [Getting Started](./getting-started.md)
- [Command Declarations](./command-declarations.md)
- [Hooks and Signals](./hooks-and-signals.md)
- [Permissions and Allowed Tools](./permissions-and-allowed-tools.md)
- [Settings](./settings.md)
- [CLI Usage](./cli.md)
- [Elixir API Usage](./elixir-api.md)
- [Troubleshooting](./troubleshooting.md)

## Architecture contract

For strict runtime signal and validation contracts, see:

- [`docs/architecture/contracts.md`](../architecture/contracts.md)
