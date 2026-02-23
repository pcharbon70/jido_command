# CLI Usage

`Jido.Code.Command.CLI` provides subcommands for command operations.

## Invocation pattern

```bash
mix run -e 'Jido.Code.Command.CLI.main(["list"])'
```

## `jido` executable

Build a local `jido` executable:

```bash
mix escript.build
```

Then call commands directly:

```bash
./jido --command code-review --params '{"target_file":"lib/foo.ex"}'
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
./jido --command code-review --params '{"target_file":"lib/foo.ex"}'
```

Options:

- `--params`, `-p`: JSON object (default `{}`)
- `--context`, `-c`: JSON object (default `{}`)
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

## Exit behavior

- Success: prints output and returns `:ok`.
- Parse/runtime errors: prints message to stderr and exits with code `1`.
- Help/version requests exit with code `0`.
