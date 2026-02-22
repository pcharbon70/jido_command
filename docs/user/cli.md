# CLI Usage

`JidoCommand.CLI` provides subcommands for command operations.

## Invocation pattern

```bash
mix run -e 'JidoCommand.CLI.main(["list"])'
```

## Subcommands

### `list`

```bash
mix run -e 'JidoCommand.CLI.main(["list"])'
```

Prints loaded command names, one per line.

### `invoke`

```bash
mix run -e 'JidoCommand.CLI.main(["invoke", "code-review", "--params", "{\"target_file\":\"lib/foo.ex\"}"])'
```

Options:

- `--params`, `-p`: JSON object (default `{}`)
- `--context`, `-c`: JSON object (default `{}`)
- `--invocation-id`: non-empty string

### `dispatch`

```bash
mix run -e 'JidoCommand.CLI.main(["dispatch", "code-review", "--params", "{\"target_file\":\"lib/foo.ex\"}"])'
```

Publishes `command.invoke` and prints JSON:

```json
{"invocation_id":"..."}
```

Options are the same as `invoke`.

### `reload`

```bash
mix run -e 'JidoCommand.CLI.main(["reload"])'
```

Reloads command registry from configured roots.

### `register-command`

```bash
mix run -e 'JidoCommand.CLI.main(["register-command", "commands/review.md"])'
```

Registers one markdown command file at runtime.

### `unregister-command`

```bash
mix run -e 'JidoCommand.CLI.main(["unregister-command", "review"])'
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
