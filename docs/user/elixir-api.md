# Elixir API Usage

`Jido.Code.Command` exposes the main runtime API.

## Functions

### `list_commands/1`

```elixir
Jido.Code.Command.list_commands()
Jido.Code.Command.list_commands(registry: MyRegistry)
```

Returns:

- `[...]` sorted command names
- `{:error, {:registry_unavailable, reason}}`

### `invoke/4`

```elixir
Jido.Code.Command.invoke("code-review", %{"target_file" => "lib/foo.ex"})

Jido.Code.Command.invoke(
  "code-review",
  %{"target_file" => "lib/foo.ex"},
  %{"source" => "api"},
  invocation_id: "invoke-123",
  bus: :jido_code_bus,
  permissions: %{allow: ["Read"], deny: [], ask: []}
)
```

Returns:

- `{:ok, result_map}`
- `{:error, reason}`

`invoke` options:

- `:registry`
- `:bus`
- `:invocation_id`
- `:permissions`

Resolution rules:

- Bus: `opts[:bus]` -> `context[:bus]`/`context["bus"]` -> `Application.get_env(:jido_command, :default_bus, :jido_code_bus)`
- Invocation ID: `opts[:invocation_id]` -> context invocation ID -> generated ID
- Binary bus names support optional leading `:` (for example `":jido_code_bus"`).
- If configured application default bus is invalid, runtime falls back to `:jido_code_bus`.

### `dispatch/4`

```elixir
Jido.Code.Command.dispatch("code-review", %{"target_file" => "lib/foo.ex"})
```

Publishes a `command.invoke` signal and returns:

- `{:ok, invocation_id}`
- `{:error, {:bus_unavailable, reason}}`
- `{:error, validation_reason}`

`dispatch` options:

- `:bus`
- `:invocation_id`

Resolution rules:

- Bus: `opts[:bus]` -> `context[:bus]`/`context["bus"]` -> `Application.get_env(:jido_command, :default_bus, :jido_code_bus)`
- Invocation ID: `opts[:invocation_id]` -> context invocation ID -> generated ID
- Binary bus names support optional leading `:` (for example `":jido_code_bus"`).
- If configured application default bus is invalid, runtime falls back to `:jido_code_bus`.

### `reload/1`

```elixir
Jido.Code.Command.reload()
Jido.Code.Command.reload(registry: MyRegistry)
```

Returns `:ok` or `{:error, reason}`.

### `register_command/2`

```elixir
Jido.Code.Command.register_command("commands/review.md")
```

Returns:

- `:ok`
- `{:error, :invalid_path}`
- `{:error, reason}`

### `unregister_command/2`

```elixir
Jido.Code.Command.unregister_command("review")
```

Returns:

- `:ok`
- `{:error, :invalid_name}`
- `{:error, reason}`

## Validation highlights

The API strictly validates:

- command name must be a non-empty string
- `params` and `context` must be maps
- options must be keyword lists with known keys only
- conflicting normalized keys in maps are rejected recursively
- context cannot include both `:invocation_id` and `"invocation_id"`

For the complete contract and error shapes, see:

- [`docs/architecture/contracts.md`](../architecture/contracts.md)
