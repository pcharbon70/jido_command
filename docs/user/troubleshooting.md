# Troubleshooting

## Common command declaration issues

| Error | Meaning | Fix |
|---|---|---|
| `{:missing_frontmatter, path}` | Command file has no YAML frontmatter block | Add `---` frontmatter with required fields |
| `{:invalid_frontmatter_field, "name", ...}` | Missing/blank `name` | Provide a non-empty `name` |
| `{:invalid_frontmatter_field, "description", ...}` | Missing/blank `description` | Provide a non-empty `description` |
| `{:invalid_frontmatter_keys, {:unknown_keys, keys}}` | Unsupported top-level keys | Remove unknown keys |
| `{:invalid_allowed_tools, :conflicting_keys}` | Both `allowed-tools` and `allowed_tools` were set | Use only one alias |
| `{:invalid_hooks, {:unknown_keys, keys}}` | Hook keys other than `pre`/`after` | Keep only `pre` and `after` |
| `{:invalid_schema_* ...}` | Schema field/options/default invalid | Match schema rules and types |

## Common invoke/dispatch payload errors

These are published as `command.failed` with an error message.

- `invalid command.invoke payload: name is required`
- `invalid command.invoke payload: params is required`
- `invalid command.invoke payload: unknown keys: ...`
- `invalid command.invoke payload: conflicting keys: ...`
- `invalid command.invoke payload: invocation_id must be a non-empty string when provided`

## Bus and registry availability errors

- `{:error, {:registry_unavailable, :noproc}}`: registry process is not running.
- `{:error, {:bus_unavailable, :noproc}}`: bus process is not running.
- `{:error, {:bus_unavailable, :invalid_bus_target}}`: bus target reference is syntactically accepted by API validation but rejected by `Jido.Signal.Bus` at publish time.

## Settings validation errors

When settings contain unknown keys or invalid values, startup logs a warning and runtime falls back to defaults.

Check:

- `<cwd>/.jido_code/settings.json`
- `~/.jido_code/settings.json`

Then run:

```bash
mix test test/config_loader_test.exs
```

## Debug checklist

1. Run `mix run -e 'Jido.Code.Command.CLI.main(["list"])'` to verify registry load.
2. Run `mix run -e 'Jido.Code.Command.CLI.main(["invoke", "<name>"])'` with minimal params.
3. Confirm command frontmatter contains only supported keys.
4. Confirm `settings.json` keys match the supported contract.
5. Subscribe to `command.failed` and `jido.hooks.after` to inspect runtime errors.
