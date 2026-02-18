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

Validation rules:

- payload data must be an object
- `name` must be a non-empty string
- `params` is required and must be an object
- `context` must be an object when provided
- `invocation_id` must be a non-empty string when provided

Invalid payloads are rejected and result in a `command.failed` signal with a validation error message.

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

## Command hook signals (`jido.hooks.pre`, `jido.hooks.after`)

These are optional per command and are declared in markdown FrontMatter under `jido.hooks`.

### `pre`

Emitted before command execution.

Data fields:

- `command` (string)
- `params` (object)
- `invocation_id` (string)
- `status` = `"pre"`

### `after`

Emitted after command execution, both success and failure.

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

- `model` (string)
- `allowed-tools` / `allowed_tools` (comma string or list of strings/atoms)
- `jido` (map)

### `jido` allowed keys

- `command_module` (Elixir module string, e.g. `MyApp.Commands.Run`)
- `hooks` (map with only `pre` and `after`)
- `schema` (map of field definitions)

Any unknown key under `jido` is rejected.

### Hook value rules

- `pre` and `after` are optional
- each value must be a non-empty string
- path is validated after `/` to `.` normalization against the signal router path validator

### Schema field rules

- field names must match `^[a-z][a-zA-Z0-9_]*$`
- supported `type` values: `string`, `integer`, `float`, `boolean`, `map`, `atom`, `list`
- supported schema option keys: `type`, `required`, `doc`, `default`
- unknown schema option keys are rejected
- `required: true` cannot be combined with `default`
