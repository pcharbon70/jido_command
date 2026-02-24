# Module Reference

Quick mapping of implementation modules to responsibilities.

## Application and public API

| Module | Responsibility |
|---|---|
| `Jido.Code.Command.Application` | Boot sequence and supervision tree wiring |
| `Jido.Code.Command` | Public API for list/invoke/dispatch/reload/register/unregister |
| `Jido.Code.Command.CLI` | Optimus-based CLI surface |

## Config

| Module | Responsibility |
|---|---|
| `Jido.Code.Command.Config.Loader` | Load + deep-merge global/local settings files |
| `Jido.Code.Command.Config.Settings` | Validate and normalize settings into runtime struct |

## Command lifecycle

| Module | Responsibility |
|---|---|
| `Jido.Code.Command.Registry` | In-memory command catalog and manual registration lifecycle |
| `Jido.Code.Command.Dispatcher` | Subscribe to `command.invoke`, validate payloads, execute async, emit result signals |
| `Jido.Code.Command.Loader` | Load command files from a directory |
| `Jido.Code.Command.Frontmatter` | Parse/validate command markdown FrontMatter |
| `Jido.Code.Command.Definition` | Canonical struct for parsed command declarations |
| `Jido.Code.Command.Compiler` | Compile command definitions into `Jido.Action` modules |
| `Jido.Code.Command.Runtime` | Execute command body with hooks/interpolation/tool filtering |

## Where to change what

- Add/adjust API validation: `Jido.Code.Command`
- Add/adjust CLI flags or subcommands: `Jido.Code.Command.CLI`
- Change command markdown schema: `CommandFrontmatter` + tests
- Change execution lifecycle or hooks: `CommandRuntime` and `CommandDispatcher`
- Change registration/reload precedence: `CommandRegistry`
- Change startup configuration behavior: `Config.Loader` / `Config.Settings`
