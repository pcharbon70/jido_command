# Signal Contracts

This document defines the runtime signal contracts implemented by the current command architecture.

## `command.invoke`

Published by API/CLI callers to request command execution.

Required data fields:

- `name` (string): registered command name
- `params` (object): command parameters

Optional data fields:

- `context` (object): execution context merged into dispatcher context
- `invocation_id` (string): caller-supplied ID; if absent dispatcher uses the inbound signal ID

For API-level dispatch (`JidoCommand.dispatch/4`), non-string or blank `invocation_id` values are normalized to a generated non-empty string before publishing.
For API-level `JidoCommand.invoke/4` and `JidoCommand.dispatch/4`, command name must be a non-empty string and both `params` and `context` must be objects; invalid inputs return an error tuple (and `dispatch` does not publish a signal).

Dispatcher-enforced execution context fields:

- `permissions` (object): normalized runtime permissions from settings (`allow`, `deny`, `ask`)

Validation rules:

- payload data must be an object
- `name` must be a non-empty string
- `params` is required and must be an object
- `context` must be an object when provided
- `invocation_id` must be a non-empty string when provided
- unknown payload keys are rejected

Invalid payloads are rejected and result in a `command.failed` signal with a validation error message.

## Settings contract (`settings.json`)

Implemented runtime keys:

- `$schema` (optional)
- `version` (optional)
- `signal_bus.name`
- `signal_bus.middleware`
- `permissions.allow` (list of strings/atoms)
- `permissions.deny` (list of strings/atoms)
- `permissions.ask` (list of strings/atoms)
- `commands.default_model`
- `commands.max_concurrent`

Permission lists are normalized by trimming values, removing empties, and de-duplicating while preserving order.

Validation rules:

- unknown top-level settings keys are rejected
- unknown keys under `signal_bus`, `permissions`, and `commands` are rejected
- `$schema` must be a non-empty string when provided
- `version` must be a valid SemVer string when provided
- `signal_bus.name` must be a non-empty string/atom when provided
- each `signal_bus.middleware` item must use supported module `Jido.Signal.Bus.Middleware.Logger`
- middleware `opts` only supports key `level`
- middleware `opts.level` must be one of `debug|info|warn|warning|error`
- `commands.default_model` must be a non-empty string when provided
- `commands.max_concurrent` must be a positive integer when provided
- permission entries must be strings/atoms (or a comma-delimited string)

## `command.completed`

Published by the dispatcher when execution succeeds.

Data fields:

- `name` (string): command name
- `invocation_id` (string)
- `result` (object): action result

## `command.failed`

Published by the dispatcher when execution fails.

Data fields:

- `name` (string)
- `invocation_id` (string)
- `error` (string)

## Registry lifecycle signals

Published by `CommandRegistry` when runtime command catalog changes.

### `command.registry.reloaded`

Published after a successful `reload`.

Data fields:

- `previous_count` (integer)
- `current_count` (integer)

### `command.registered`

Published after registering one command file at runtime.

Data fields:

- `name` (string)
- `path` (string): absolute path to markdown file
- `scope` (string): current value is `"manual"`
- `current_count` (integer)

### `command.unregistered`

Published after unregistering a command by name.

Data fields:

- `name` (string)
- `current_count` (integer)

### `command.registry.failed`

Published when a registry lifecycle operation fails.

Common data fields:

- `operation` (string): one of `reload`, `register`, `unregister`
- `error` (string)

Optional data fields by operation:

- `reload`: `previous_count` (integer), `current_count` (integer)
- `register`: `path` (string)
- `unregister`: `name` (string)

Registry validation rule:

- `register_command` rejects blank command paths with `invalid_path`
- `register_command` rejects non-string command paths with `invalid_path`
- `unregister_command` rejects blank or non-string command names with `invalid_name`

Public API validation rules:

- `JidoCommand.register_command/2` requires a non-empty string path and returns `{:error, :invalid_path}` for invalid input
- `JidoCommand.unregister_command/2` requires a non-empty string name and returns `{:error, :invalid_name}` for invalid input

## Command hook signals (`jido.hooks.pre`, `jido.hooks.after`)

These are optional per command and are declared in markdown FrontMatter under `jido.hooks`.

### `pre`

Emitted before command execution.

Data fields:

- `command` (string)
- `params` (object)
- `invocation_id` (string)
- `status` = `"pre"`

Runtime behavior: if context does not provide a valid non-empty string invocation ID, runtime generates one.

### `after`

Emitted after command execution, both success and failure.
This includes executor-returned errors and executor exceptions.

Success data fields:

- `command` (string)
- `params` (object)
- `invocation_id` (string)
- `duration_ms` (integer)
- `status` = `"ok"`
- `result` (object)

Failure data fields:

- `command` (string)
- `params` (object)
- `invocation_id` (string)
- `duration_ms` (integer)
- `status` = `"error"`
- `error` (string)

## Command FrontMatter contract (Phase 3)

Markdown command declarations must include YAML frontmatter with these required keys:

- `name` (non-empty string)
- `description` (non-empty string)

Optional keys:

- `model` (non-empty string)
- `allowed-tools` / `allowed_tools` (non-empty comma string or non-empty list of strings/atoms)
- `jido` (map)

Any unknown top-level FrontMatter key is rejected.

### Allowed tools rules

- when provided, `allowed-tools` / `allowed_tools` must resolve to at least one non-empty tool name
- blank strings are rejected
- empty lists are rejected
- list or comma-string entries are trimmed; empty entries are ignored
- after trimming and normalization, duplicate tool names are de-duplicated in source order

### `jido` allowed keys

- `command_module` (Elixir module string, e.g. `MyApp.Commands.Run`)
- `hooks` (map with only `pre` and `after`)
- `schema` (map of field definitions)

Any unknown key under `jido` is rejected.

### Hook value rules

- `pre` and `after` are optional
- each value must be a boolean when provided
- `true` enables emission of the predefined signal for that phase
- `false` (or omitted) disables emission for that phase

### Schema field rules

- field names must match `^[a-z][a-zA-Z0-9_]*$`
- supported `type` values: `string`, `integer`, `float`, `boolean`, `map`, `atom`, `list`
- supported schema option keys: `type`, `required`, `doc`, `default`
- unknown schema option keys are rejected
- `required: true` cannot be combined with `default`
- when `default` is provided, its value must match the declared `type`
- atom defaults declared as YAML strings are normalized to atoms in the compiled schema
