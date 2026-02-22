# Permissions and Allowed Tools

Tool access is controlled by two layers:

- Runtime permissions (`allow`, `deny`, `ask`)
- Per-command `allowed-tools` declaration

## Runtime permissions

Runtime permissions come from settings (and can be overridden in API `invoke` options):

```json
{
  "permissions": {
    "allow": ["Read", "Write"],
    "deny": ["Bash(rm -rf:*)"],
    "ask": ["Bash(npm:*)"]
  }
}
```

Dispatcher injects normalized permissions into command context as:

```elixir
%{permissions: %{allow: [...], deny: [...], ask: [...]}}
```

## `allowed-tools` as command filter

If a command declares `allowed-tools`, runtime applies it as a top-level filter before command execution.

Effect:

- Permissions outside `allowed-tools` are removed from `allow`, `deny`, and `ask`.
- Command context gets normalized `:allowed_tools` and `:permissions`.
- If `allowed-tools` is not declared, runtime permissions remain as-is (after normalization).

## Wildcard behavior

Wildcard entries (`*`) are string-pattern matches.

Examples:

- `Bash(git diff:*)` matches `Bash(git diff:--stat)`.
- `Bash(git:*)` does not match `Bash(git diff:--stat)`.

When `allowed-tools` uses wildcards, exact matching permission entries are preserved in reduced buckets.

## Example

Command declaration:

```yaml
allowed-tools:
  - Read
  - Bash(git diff:*)
```

Runtime permissions:

```elixir
%{
  allow: ["Read", "Write", "Bash(git diff:--stat)"],
  deny: ["Bash(rm -rf:*)", "Bash(git diff:--cached)"],
  ask: ["Grep", "Bash(git diff:--name-only)"]
}
```

Effective command permissions become:

```elixir
%{
  allow: ["Read", "Bash(git diff:--stat)"],
  deny: ["Bash(git diff:--cached)"],
  ask: ["Bash(git diff:--name-only)"]
}
```
