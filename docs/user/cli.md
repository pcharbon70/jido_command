# CLI Usage

`Jido.Code.Command.CLI` provides subcommands for command operations.

## Invocation pattern

```bash
mix run -e 'Jido.Code.Command.CLI.main(["list"])'
```

## `command` executable

Build a local `command` executable:

```bash
mix escript.build
```

Then call commands directly:

```bash
./command code-review --params '{"target_file":"lib/foo.ex"}'
```

You can also pass command params directly as top-level options:

```bash
./command code-review --target-file lib/foo.ex --max-results 10 --dry-run
```

Or load params/context from JSON files:

```bash
./command code-review --params-file params.json --context-file context.json
```

Optional global install:

```bash
mix do escript.build + escript.install
```

If needed, add `~/.mix/escripts` to your `PATH`.
Set `JIDO_COMMAND_TZDATA_DIR` if you want a custom timezone data directory for the executable.
If `JIDO_COMMAND_TZDATA_DIR` is not set, the executable auto-seeds timezone release data from its embedded archive.
If the configured timezone directory cannot be prepared, the executable falls back to a temp runtime directory.

## Subcommands

### `list`

```bash
mix run -e 'Jido.Code.Command.CLI.main(["list"])'
```

Prints loaded command names, one per line.

### `invoke`

```bash
mix run -e 'Jido.Code.Command.CLI.main(["invoke", "code-review", "--params", "{\"target_file\":\"lib/foo.ex\"}"])'
```

Equivalent shorthand via escript:

```bash
./command code-review --params '{"target_file":"lib/foo.ex"}'
```

With file inputs:

```bash
./command code-review --params-file params.json --context-file context.json
```

Top-level command invocation also accepts command params directly:

```bash
./command code-review --target-file lib/foo.ex --include-tests true
```

When a command name conflicts with a CLI subcommand, use `--` to force command invocation:

```bash
./command -- list --target-file lib/foo.ex
```

Shorthand param rules:

- unknown `--<name>` options are treated as command params
- `--name value` and `--name=value` are both supported
- bare flags (for example `--dry-run`) become boolean `true`
- param names normalize `-` to `_` (for example `--target-file` -> `target_file`)
- values are JSON-decoded when valid JSON (numbers, booleans, objects, arrays, `null`), otherwise treated as strings
- reserved options remain runtime options: `--params`, `--params-file`, `-p`, `--context`, `--context-file`, `-c`, `--invocation-id`, `--bus`
- `--` before the command name forces top-level command invocation and bypasses subcommand matching

Options:

- `--params`, `-p`: JSON object (default `{}`)
- `--params-file`: path to JSON file containing an object; merged before inline `--params` (inline keys win)
- `--context`, `-c`: JSON object (default `{}`)
- `--context-file`: path to JSON file containing an object; merged before inline `--context` (inline keys win)
- `--invocation-id`: non-empty string
- `--bus`: non-empty bus target string (for example `:jido_code_bus`)

### `dispatch`

```bash
mix run -e 'Jido.Code.Command.CLI.main(["dispatch", "code-review", "--params", "{\"target_file\":\"lib/foo.ex\"}"])'
```

Publishes `command.invoke` and prints JSON:

```json
{"invocation_id":"..."}
```

Options are the same as `invoke`.

### `reload`

```bash
mix run -e 'Jido.Code.Command.CLI.main(["reload"])'
```

Reloads command registry from configured roots.

### `register-command`

```bash
mix run -e 'Jido.Code.Command.CLI.main(["register-command", "commands/review.md"])'
```

Registers one markdown command file at runtime.

### `unregister-command`

```bash
mix run -e 'Jido.Code.Command.CLI.main(["unregister-command", "review"])'
```

Unregisters one command by name.

## JSON parsing rules

`--params` and `--context` must decode to JSON objects.

- Valid: `{"x":1}`
- Invalid: `[1,2,3]`

`--params-file` and `--context-file` must reference readable files whose contents decode to JSON objects.

## Exit behavior

- Success: prints output and returns `:ok`.
- Parse/runtime errors: prints message to stderr and exits with code `1`.
- Help/version requests exit with code `0`.
