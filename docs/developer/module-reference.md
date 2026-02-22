# Module Reference

Quick mapping of implementation modules to responsibilities.

## Application and public API

| Module | Responsibility |
|---|---|
| `JidoCommand.Application` | Boot sequence and supervision tree wiring |
| `JidoCommand` | Public API for list/invoke/dispatch/reload/register/unregister |
| `JidoCommand.CLI` | Optimus-based CLI surface |

## Config

| Module | Responsibility |
|---|---|
| `JidoCommand.Config.Loader` | Load + deep-merge global/local settings files |
| `JidoCommand.Config.Settings` | Validate and normalize settings into runtime struct |

## Command lifecycle

| Module | Responsibility |
|---|---|
| `JidoCommand.Extensibility.CommandRegistry` | In-memory command catalog and manual registration lifecycle |
| `JidoCommand.Extensibility.CommandDispatcher` | Subscribe to `command.invoke`, validate payloads, execute async, emit result signals |
| `JidoCommand.Extensibility.CommandLoader` | Load command files from a directory |
| `JidoCommand.Extensibility.CommandFrontmatter` | Parse/validate command markdown FrontMatter |
| `JidoCommand.Extensibility.CommandDefinition` | Canonical struct for parsed command declarations |
| `JidoCommand.Extensibility.Command` | Compile command definitions into `Jido.Action` modules |
| `JidoCommand.Extensibility.CommandRuntime` | Execute command body with hooks/interpolation/tool filtering |

## Where to change what

- Add/adjust API validation: `JidoCommand`
- Add/adjust CLI flags or subcommands: `JidoCommand.CLI`
- Change command markdown schema: `CommandFrontmatter` + tests
- Change execution lifecycle or hooks: `CommandRuntime` and `CommandDispatcher`
- Change registration/reload precedence: `CommandRegistry`
- Change startup configuration behavior: `Config.Loader` / `Config.Settings`
