# Contributing Guide

## Local development workflow

1. Install dependencies.
2. Make focused changes in small commits.
3. Run quality checks before opening a PR.

## Quality checks

```bash
mix test
mix credo --strict
mix dialyzer
```

## Coding expectations

- Keep runtime contracts explicit and strict.
- Preserve compatibility of documented signal payloads.
- Prefer small private helpers over deeply nested control flow.
- Normalize and validate input close to module boundaries.

## Documentation expectations

When behavior changes:

- Update user guides in `docs/user` when external behavior changes.
- Update developer guides in `docs/developer` for internal architecture changes.
- Update `docs/architecture/contracts.md` for signal or validation contract changes.

## Pull request checklist

- Tests added/updated for changed behavior.
- Quality checks pass (`test`, `credo`, `dialyzer`).
- Docs updated where contracts or usage changed.
- Change is scoped to one coherent concern.
