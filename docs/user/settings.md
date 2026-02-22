# Settings

The runtime loads and merges two `settings.json` files.

## Locations

- Global: `~/.jido_code/settings.json`
- Local: `<cwd>/.jido_code/settings.json`

Merge behavior:

- Local overrides global.
- Maps are merged deeply.
- Missing files are treated as empty objects.

## Supported top-level keys

- `$schema` (optional non-empty string)
- `version` (optional SemVer string)
- `signal_bus`
- `permissions`
- `commands`

Unknown top-level keys are rejected.

## `signal_bus`

Supported keys:

- `name` (non-empty string or atom)
- `middleware` (list)

Supported middleware item:

- `module`: `Jido.Signal.Bus.Middleware.Logger`
- `opts.level`: `debug`, `info`, `warn`, `warning`, or `error`

## `permissions`

Supported keys:

- `allow`
- `deny`
- `ask`

Each value can be:

- list of strings/atoms
- comma-separated string

Values are trimmed, blanks removed, and de-duplicated.

## `commands`

Supported keys:

- `default_model` (non-empty string)
- `max_concurrent` (positive integer)

## Example

```json
{
  "$schema": "https://jidocode.dev/schemas/settings.json",
  "version": "2.0.0",
  "signal_bus": {
    "name": ":jido_code_bus",
    "middleware": [
      {
        "module": "Jido.Signal.Bus.Middleware.Logger",
        "opts": {"level": "debug"}
      }
    ]
  },
  "permissions": {
    "allow": ["Read", "Write", "Bash(git diff:*)"],
    "deny": ["Bash(rm -rf:*)"],
    "ask": ["Bash(npm:*)"]
  },
  "commands": {
    "default_model": "claude-sonnet-4-20250514",
    "max_concurrent": 5
  }
}
```

## Startup behavior on invalid settings

`Jido.Code.Command.Application` attempts to load settings at boot.

- If settings are valid, they configure bus, registry, dispatcher, and defaults.
- If settings load/validation fails, runtime logs a warning and falls back to built-in defaults.
