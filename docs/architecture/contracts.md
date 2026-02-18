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

## `extension.loaded`

Published by extension registry after loading one extension manifest.

Data fields:

- `extension_name` (string)
- `version` (string)

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
