# JidoCode Command Extensibility System Design (Jido v2)

**A command-only architecture with two optional FrontMatter hook signals**

This design keeps extensibility focused on slash commands and Jido Signal Bus pub/sub. Hooks are reduced to exactly two predefined signal hooks declared per command in FrontMatter:

- `pre`: emitted before command execution
- `after`: emitted after command execution (success or failure)

## Scope and core primitives

Jido v2 primitives used in this architecture:

- **Commands**: `Jido.Action` modules with Zoi schemas
- **Hook signals**: two predefined command lifecycle signals (`pre`, `after`)
- **Pub/Sub**: `JidoSignal.Bus` as the only event transport
- **Extensions**: packaged command bundles loaded at runtime

| Extensibility Concept | Jido v2 Primitive | Implementation Pattern |
|-----------------------|-------------------|------------------------|
| Slash Command | `Jido.Action` | Action module generated from markdown frontmatter |
| Pre/After Hook | `JidoSignal.Signal` | Optional signal paths from command FrontMatter |
| Extension | Supervision + registry | Runtime registration of command modules |

## Jido v2 dependency structure

```text
jido/           # Core runtime
jido_action/    # Action primitive with Zoi validation
jido_signal/    # Signal primitive with Bus (CloudEvents v1.0.2)
```

## Directory layout (global + project)

```text
~/.jido_code/
├── settings.json
├── JIDO.md
├── commands/
│   └── *.md
├── extensions/
│   └── extension-name/
│       └── .jido-extension/
│           └── extension.json
└── logs/

.jido_code/
├── settings.json
├── JIDO.md
├── commands/
│   └── *.md
└── extensions/
```

Local config overrides global config during merge.

## settings.json schema (signal bus + command runtime)

```json
{
  "$schema": "https://jidocode.dev/schemas/settings.json",
  "version": "2.0.0",

  "signal_bus": {
    "name": ":jido_code_bus",
    "middleware": [
      {
        "module": "JidoSignal.Bus.Middleware.Logger",
        "opts": { "level": "debug" }
      }
    ]
  },

  "permissions": {
    "allow": ["Bash(git:*)", "Read", "Write", "Edit"],
    "deny": ["Bash(rm -rf:*)"],
    "ask": ["Bash(npm:*)"]
  },

  "commands": {
    "default_model": "claude-sonnet-4-20250514",
    "max_concurrent": 5
  },

  "extensions": {
    "enabled": ["git-tools", "code-analyzer"],
    "disabled": [],
    "marketplaces": {
      "community": {
        "source": "github",
        "repo": "jidocode/extension-marketplace"
      }
    }
  }
}
```

## Markdown format for commands with predefined hooks

Commands remain markdown-first with YAML frontmatter and Jido extensions.

```yaml
---
name: code-review
description: Review changed files for quality and security concerns.
model: sonnet
allowed-tools: Read, Grep, Glob, Bash(git diff:*)

jido:
  command_module: JidoCode.Commands.CodeReview
  schema:
    review_depth: Zoi.atom(values: [:quick, :standard, :thorough], default: :standard)
    focus_areas: Zoi.list(Zoi.string(), default: [:security, :performance])

  hooks:
    pre: "commands/code_review/pre"
    after: "commands/code_review/after"
---

You are an expert Elixir code reviewer.

## Output
- Critical: Security vulnerabilities
- Warning: Performance and maintainability issues
- Info: Style and clarity improvements
```

### Hook behavior

- `jido.hooks.pre` is optional; if present, it is emitted immediately before execution.
- `jido.hooks.after` is optional; if present, it is emitted once execution finishes.
- `after` is emitted for both success and failure with a `status` field (`"ok"` or `"error"`).

## Extension manifest (commands only)

```json
{
  "$schema": "https://jidocode.dev/schemas/extension.json",
  "name": "code-quality",
  "version": "2.1.0",
  "description": "Code quality command pack",
  "author": {
    "name": "JidoCode Community",
    "email": "extensions@jidocode.dev"
  },
  "license": "MIT",
  "repository": "https://github.com/jidocode/extension-code-quality",
  "keywords": ["commands", "linting", "security"],

  "elixir": {
    "application": "JidoCodeQuality",
    "mix_deps": [
      {":jido", "~> 2.0"},
      {":jido_signal", "~> 1.2"},
      {":jido_action", "~> 1.0"},
      {":credo", "~> 1.7"},
      {":sobelow", "~> 0.13"}
    ]
  },

  "commands": "./commands",

  "signals": {
    "emits": [
      "commands/code_review/pre",
      "commands/code_review/after",
      "command/completed",
      "command/failed"
    ],
    "subscribes": [
      "command/invoke"
    ]
  }
}
```

## Elixir architecture using command + signal patterns

### Extension registry and loader

```elixir
defmodule JidoCode.Extensibility.ExtensionRegistry do
  @moduledoc """
  Central registry for loaded extensions and commands.
  """
  use GenServer

  alias JidoSignal.Signal
  alias JidoSignal.Bus

  defstruct extensions: %{}, commands: %{}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def init(opts) do
    Bus.subscribe(:jido_code_bus, "extension/created", dispatch: {:pid, target: self()})
    {:ok, load_all_extensions(%__MODULE__{}, opts)}
  end

  def register_extension(manifest), do: GenServer.call(__MODULE__, {:register_extension, manifest})
  def get_command(name), do: GenServer.call(__MODULE__, {:get_command, name})

  def handle_call({:register_extension, manifest}, _from, state) do
    extension = load_extension_from_manifest(manifest)

    {:ok, signal} = Signal.new(
      "extension/loaded",
      %{extension_name: manifest.name, version: manifest.version},
      source: "/extensions/#{manifest.name}"
    )

    Bus.publish(:jido_code_bus, [signal])

    new_state = %{state |
      extensions: Map.put(state.extensions, manifest.name, extension),
      commands: Map.merge(state.commands, extension.commands)
    }

    {:reply, {:ok, extension}, new_state}
  end
end
```

### Action-based slash command implementation

```elixir
defmodule JidoCode.Extensibility.Command do
  @moduledoc """
  Slash commands implemented as Jido Actions with markdown configuration.
  Only two predefined hooks are supported: pre and after.
  """

  alias JidoSignal.Signal
  alias JidoSignal.Bus

  def from_markdown(path) do
    {:ok, content} = File.read(path)
    {frontmatter, body} = parse_frontmatter(content)

    schema = build_zoi_schema_from_frontmatter(frontmatter)
    hooks = get_in(frontmatter, ["jido", "hooks"]) || %{}
    module_name = module_name_from_path(path)

    Module.create(module_name, quote do
      use Jido.Action,
        name: unquote(frontmatter["name"] || Path.basename(path, ".md")),
        description: unquote(frontmatter["description"]),
        schema: unquote(schema)

      @allowed_tools unquote(parse_tools(frontmatter["allowed-tools"]))
      @prompt_body unquote(body)
      @hook_pre unquote(hooks["pre"])
      @hook_after unquote(hooks["after"])

      @impl true
      def run(params, context) do
        emit_hook(@hook_pre, %{command: __MODULE__, params: params})

        case safe_execute(params, context) do
          {:ok, result} ->
            emit_hook(@hook_after, %{command: __MODULE__, status: "ok", result: result})
            result

          {:error, error, stacktrace} ->
            emit_hook(@hook_after, %{command: __MODULE__, status: "error", error: inspect(error)})
            :erlang.raise(:error, error, stacktrace)
        end
      end

      defp safe_execute(params, context) do
        {:ok, execute_with_tools(interpolate_prompt(@prompt_body, params), @allowed_tools, context)}
      rescue
        error -> {:error, error, __STACKTRACE__}
      end

      defp emit_hook(nil, _payload), do: :ok

      defp emit_hook(type, payload) do
        {:ok, signal} = Signal.new(type, payload, source: "/commands/#{__MODULE__}")
        Bus.publish(:jido_code_bus, [signal])
      end
    end, Macro.Env.location(__ENV__))

    {:ok, module_name}
  end
end
```

### Command dispatch loop via signal paths

```elixir
defmodule JidoCode.Extensibility.CommandDispatcher do
  @moduledoc """
  Listens for command invocation signals and executes registered commands.
  """

  alias JidoSignal.Signal
  alias JidoSignal.Bus
  alias JidoCode.Extensibility.ExtensionRegistry

  def init do
    Bus.subscribe(:jido_code_bus, "command/invoke", dispatch: {:pid, target: self()})
    :ok
  end

  def handle_info({:signal, %{type: "command/invoke", data: %{"name" => name, "params" => params}}}, state) do
    with {:ok, command} <- ExtensionRegistry.get_command(name),
         {:ok, result} <- command.run(params, %{}) do
      {:ok, completed} = Signal.new("command/completed", %{name: name, result: result}, source: "/dispatcher")
      Bus.publish(:jido_code_bus, [completed])
      {:noreply, state}
    else
      {:error, reason} ->
        {:ok, failed} = Signal.new("command/failed", %{name: name, error: inspect(reason)}, source: "/dispatcher")
        Bus.publish(:jido_code_bus, [failed])
        {:noreply, state}
    end
  end
end
```

## Application supervision tree

```elixir
defmodule JidoCode.Application do
  use Application

  def start(_type, _args) do
    children = [
      {JidoSignal.Bus, [
        name: :jido_code_bus,
        middleware: [{JidoSignal.Bus.Middleware.Logger, level: :debug}]
      ]},
      {JidoCode.Extensibility.ExtensionRegistry, [
        global_path: Path.expand("~/.jido_code"),
        local_path: ".jido_code"
      ]},
      JidoCode.Extensibility.CommandDispatcher
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: JidoCode.Supervisor)
  end
end
```

## Key integration points

- **Commands are the only execution abstraction**: each command is a `Jido.Action` compiled from markdown.
- **Exactly two predefined hooks exist**: `pre` and `after`, both declared optionally in command FrontMatter.
- **Hook transport is signal-only**: hooks emit `JidoSignal.Signal` events on `JidoSignal.Bus`.
- **No global hook registry is needed**: hook behavior lives with each command declaration.

## Jido v1 to v2 notes for this design

| Aspect | Jido v1 | Jido v2 |
|--------|---------|---------|
| Routing style | Pattern-based (`"extension.**"`) | Path-based (`"extension/loaded"`) |
| Command schema | NimbleOptions | Zoi schemas |
| Signal format | Custom | CloudEvents v1.0.2 |
| Dependencies | Monolithic | Modular (`jido`, `jido_action`, `jido_signal`) |
| Runtime effects | Implicit | Explicit event flow through `JidoSignal.Bus` |
