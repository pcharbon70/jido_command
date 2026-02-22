# Hooks and Signals

The runtime is signal-driven. It uses the bus for command dispatch, results, and optional hook events.

## Core command signals

### `command.invoke`

Request command execution.

Required data fields:

- `name` (string)
- `params` (object)

Optional data fields:

- `context` (object)
- `invocation_id` (non-empty string)

### `command.completed`

Published when execution succeeds.

- `name`
- `invocation_id`
- `result`

### `command.failed`

Published when execution fails.

- `name`
- `invocation_id`
- `error`

## Hook signals

Hooks are declared per command in FrontMatter under `jido.hooks`.
Hook publication is best-effort. If hook signal publish fails, command execution still proceeds.

### `jido.hooks.pre`

Emitted before execution when `pre: true`.

Payload fields:

- `command`
- `params`
- `invocation_id`
- `status: "pre"`

### `jido.hooks.after`

Emitted after execution when `after: true`.

Success payload includes:

- `command`
- `params`
- `invocation_id`
- `duration_ms`
- `status: "ok"`
- `result`

Failure payload includes:

- `command`
- `params`
- `invocation_id`
- `duration_ms`
- `status: "error"`
- `error`

## Registry lifecycle signals

The registry also publishes lifecycle events:

- `command.registry.reloaded`
- `command.registered`
- `command.unregistered`
- `command.registry.failed`

These are useful for observing dynamic command catalog changes.

## Subscribing example

```elixir
alias Jido.Signal.Bus

{:ok, _id} = Bus.subscribe(:jido_code_bus, "command.completed", dispatch: {:pid, target: self()})

receive do
  {:signal, signal} ->
    IO.inspect(signal.type)
    IO.inspect(signal.data)
end
```

## Signal contract reference

For full validation and payload error behavior, see:

- [`docs/architecture/contracts.md`](../architecture/contracts.md)
