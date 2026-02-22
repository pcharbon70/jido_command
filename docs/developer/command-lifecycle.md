# Command Lifecycle

This page documents how commands move through runtime paths.

## Path A: Direct API invoke (`JidoCommand.invoke/4`)

```mermaid
sequenceDiagram
  participant Caller as "Caller"
  participant API as "JidoCommand.invoke/4"
  participant Registry as "CommandRegistry"
  participant Action as "Compiled Jido.Action"
  participant Runtime as "CommandRuntime"
  participant Bus as "Signal Bus"

  Caller->>API: "invoke(name, params, context, opts)"
  API->>API: "Validate options, name, params, context"
  API->>Registry: "get_command(name)"
  Registry-->>API: "{:ok, module}"
  API->>API: "Resolve bus, invocation_id, permissions"
  API->>Action: "Jido.Exec.run(module, params, context)"
  Action->>Runtime: "execute(definition, params, context)"
  Runtime->>Bus: "Optional jido.hooks.pre"
  Runtime->>Runtime: "Interpolate template + execute"
  Runtime->>Bus: "Optional jido.hooks.after"
  Runtime-->>Action: "{:ok | :error, result}"
  Action-->>API: "{:ok | :error, result}"
  API-->>Caller: "Return invoke result"
```

Notes:

- `invoke/4` returns execution result directly.
- `command.completed` / `command.failed` are not emitted on this direct path.

## Path B: Signal dispatch (`JidoCommand.dispatch/4` -> dispatcher)

```mermaid
sequenceDiagram
  participant Caller as "Caller"
  participant API as "JidoCommand.dispatch/4"
  participant Bus as "Signal Bus"
  participant Dispatcher as "CommandDispatcher"
  participant Registry as "CommandRegistry"
  participant Action as "Compiled Jido.Action"

  Caller->>API: "dispatch(name, params, context, opts)"
  API->>API: "Validate inputs and options"
  API->>Bus: "Publish command.invoke"
  API-->>Caller: "{:ok, invocation_id}"

  Bus->>Dispatcher: "Deliver command.invoke"
  Dispatcher->>Dispatcher: "Validate payload"
  Dispatcher->>Dispatcher: "Queue or start (max_concurrent)"
  Dispatcher->>Registry: "get_command(name)"
  Registry-->>Dispatcher: "{:ok, module} or error"
  Dispatcher->>Action: "Jido.Exec.run(module, params, context)"
  Dispatcher->>Bus: "Publish command.completed or command.failed"
```

Notes:

- Dispatcher always publishes completion/failure signals for the dispatch path.
- Invalid payloads are converted to `command.failed` with explicit validation messages.
- Execution is asynchronous with queue backpressure (`max_concurrent`).

## Runtime-managed context keys

Before execution, runtime normalizes and injects:

- `:bus`
- `:invocation_id`
- `:permissions`

String aliases (`"bus"`, `"invocation_id"`, `"permissions"`) are removed when these runtime-managed keys are applied.
