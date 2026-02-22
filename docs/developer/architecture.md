# Architecture

`jido_command` is a command-only runtime. Commands are markdown declarations compiled into `Jido.Action` modules and executed either directly (`invoke`) or through bus signals (`dispatch` + dispatcher).

## Supervisor topology

```mermaid
flowchart TD
  A["JidoCommand.Supervisor"] --> B["Jido.Signal.Bus"]
  A --> C["JidoCommand.Extensibility.CommandRegistry"]
  A --> D["JidoCommand.Extensibility.CommandDispatcher"]
  D -->|"Subscribes to command.invoke"| B
  C -->|"Publishes registry lifecycle signals"| B
```

## Runtime component map

```mermaid
flowchart LR
  U["Caller (CLI/API)"] --> V["JidoCommand Public API"]

  V -->|"invoke/4"| R["CommandRegistry"]
  R --> M["Compiled Jido.Action module"]
  M --> X["CommandRuntime.execute/3"]
  X -->|"Hook signals"| B["Signal Bus"]

  V -->|"dispatch/4 publishes command.invoke"| B
  B --> D["CommandDispatcher"]
  D -->|"Lookup command"| R
  D -->|"Executes command"| M
  D -->|"Publishes command.completed/command.failed"| B
```

## Key invariants

- Commands are loaded from both global and local roots, with local precedence.
- Command payload validation is strict for both public API and dispatcher input.
- Runtime-managed context keys are normalized before execution: `:bus`, `:invocation_id`, `:permissions`.
- Only two optional hook signals are supported: `jido.hooks.pre` and `jido.hooks.after`.
- No extension/manifest abstraction is used; command markdown is the only dynamic declaration surface.

## Important modules

- `JidoCommand`: public API (`list_commands`, `invoke`, `dispatch`, `reload`, `register_command`, `unregister_command`)
- `JidoCommand.Application`: boot, settings load, supervision
- `JidoCommand.Config.Loader` / `JidoCommand.Config.Settings`: settings merge + validation
- `JidoCommand.Extensibility.CommandRegistry`: command catalog and runtime registration
- `JidoCommand.Extensibility.CommandDispatcher`: `command.invoke` subscriber and async execution queue
- `JidoCommand.Extensibility.CommandFrontmatter`: command markdown parser + validation
- `JidoCommand.Extensibility.Command`: compilation to `Jido.Action` modules
- `JidoCommand.Extensibility.CommandRuntime`: template interpolation, hook emission, permission filtering
