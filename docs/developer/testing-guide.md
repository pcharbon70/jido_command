# Testing Guide

This project uses ExUnit with focused module-level test suites.

## Run tests

```bash
mix test
```

Run a specific file:

```bash
mix test test/command_runtime_test.exs
```

## Test suite map

| File | Coverage |
|---|---|
| `test/jido_command_test.exs` | Public API validation and behavior |
| `test/cli_test.exs` | CLI parsing, runtime delegation, exit behavior |
| `test/command_frontmatter_test.exs` | FrontMatter parsing and validation |
| `test/command_compiler_test.exs` | Command compilation behavior |
| `test/command_runtime_test.exs` | Hooks, interpolation, permission filtering |
| `test/command_dispatcher_test.exs` | `command.invoke` processing and emitted signals |
| `test/command_registry_test.exs` | Registry load/reload/register/unregister behavior |
| `test/config_loader_test.exs` | Settings load/merge/validation behavior |

## High-value regression tests to keep

- Strict rejection of unknown/conflicting keys in payloads and settings.
- Hook emission behavior for both success and failure.
- `allowed-tools` wildcard filtering edge cases.
- Dispatcher queue behavior under `max_concurrent` constraints.
- Registry behavior when manual registrations overlap with loaded commands.

## Adding new tests

1. Add unit tests closest to the module change.
2. If behavior affects contracts, add assertions to the related signal/payload tests.
3. Prefer explicit error-shape assertions over loose pattern checks.
4. Keep fixtures minimal and local to each test case.
