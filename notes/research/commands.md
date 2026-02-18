# JidoCode Command Extensibility System Design (Jido v2)

**A signal bus-first command architecture using Jido v2 primitives**

This design keeps extensibility focused on **slash commands** and **hooks**, with all runtime messaging handled through the **Jido Signal Bus**.

## Scope and core primitives

Jido v2 provides the primitives needed for a command-only architecture:

- **Commands**: `Jido.Action` modules with Zoi schemas
- **Hooks**: lifecycle subscriptions and reactions expressed as `JidoSignal.Signal` events
- **Pub/Sub**: `JidoSignal.Bus` as the single event backbone
- **Extensions**: OTP-supervised packages that register commands and hook policies

| Extensibility Concept | Jido v2 Primitive | Implementation Pattern |
|-----------------------|-------------------|------------------------|
| Slash Command | `Jido.Action` | Action module generated from markdown frontmatter |
| Hook | `JidoSignal.Bus` + `JidoSignal.Signal` | Subscribe to lifecycle paths and emit follow-up signals |
| Extension | Supervision tree + registry | Runtime registration of commands and hook rules |

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
├── hooks/
│   └── *.json
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
├── hooks/
│   └── *.json
└── extensions/
```

Local config overrides global config during merge.

## settings.json schema (signal bus + signal hooks)

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

  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit",
        "emit": [
          {
            "signal_type": "hooks/pre_tool_use/edit",
            "data_template": {
              "tool": "{{tool_name}}",
              "timestamp": "{{timestamp}}"
            }
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "emit": [
          {
            "signal_type": "hooks/post_tool_use",
            "data_template": {
              "tool": "{{tool_name}}",
              "duration_ms": "{{duration_ms}}"
            }
          }
        ]
      }
    ],
    "Error": [
      {
        "matcher": "*",
        "emit": [
          {
            "signal_type": "hooks/error",
            "data_template": {
              "error": "{{error_message}}",
              "context": "{{context}}"
            }
          }
        ]
      }
    ]
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

### Hook action specification

Only one hook action type is supported:

| Action Type | Fields | Description |
|-------------|--------|-------------|
| `signal` | `signal_type`, `data_template`, `bus` (optional) | Emit a Jido signal when a hook matcher is triggered |

## Markdown format for slash commands

Commands remain markdown-first with YAML frontmatter and Jido extensions:

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

  signals:
    emit:
      on_start: "commands/code_review/started"
      on_finding: "commands/code_review/finding"
      on_complete: "commands/code_review/completed"
      on_error: "commands/code_review/error"
---

You are an expert Elixir code reviewer.

## Output
- Critical: Security vulnerabilities
- Warning: Performance and maintainability issues
- Info: Style and clarity improvements
```

### In-prompt signal directive syntax

```markdown
@signal(path) { JSON payload with {{variable}} interpolation }
@signal(commands/code_review/progress) { "step": {{current_step}}, "total": {{total_steps}} }
```

Directives compile to `JidoSignal.Signal` emissions on the configured bus.

## Extension manifest (commands + hook signals)

```json
{
  "$schema": "https://jidocode.dev/schemas/extension.json",
  "name": "code-quality",
  "version": "2.1.0",
  "description": "Code quality and security command pack",
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
  "hooks": "./config/hooks.json",

  "signals": {
    "emits": [
      "commands/code_review/finding",
      "commands/code_review/completed",
      "hooks/post_tool_use"
    ],
    "subscribes": [
      "lifecycle/pre_tool_use",
      "lifecycle/post_tool_use",
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
  Central registry for loaded extensions, commands, and hook rules.
  """
  use GenServer

  alias JidoSignal.Signal
  alias JidoSignal.Bus

  defstruct extensions: %{}, commands: %{}, hooks: %{}

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
      commands: Map.merge(state.commands, extension.commands),
      hooks: merge_hook_rules(state.hooks, extension.hooks)
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
  """

  alias JidoSignal.Signal
  alias JidoSignal.Bus

  defmacro __using__(opts) do
    quote do
      use Jido.Action,
        name: unquote(opts[:name]),
        description: unquote(opts[:description]),
        schema: unquote(opts[:schema] || Zoi.object(%{}))

      @command_config unquote(opts)
      def __command_config__, do: @command_config
    end
  end

  def from_markdown(path) do
    {:ok, content} = File.read(path)
    {frontmatter, body} = parse_frontmatter(content)

    schema = build_zoi_schema_from_frontmatter(frontmatter)
    module_name = module_name_from_path(path)

    Module.create(module_name, quote do
      use Jido.Action,
        name: unquote(frontmatter["name"] || Path.basename(path, ".md")),
        description: unquote(frontmatter["description"]),
        schema: unquote(schema)

      @allowed_tools unquote(parse_tools(frontmatter["allowed-tools"]))
      @prompt_body unquote(body)
      @signal_config unquote(get_in(frontmatter, ["jido", "signals"]) || %{})

      @impl true
      def run(params, context) do
        emit_signal(@signal_config["emit"]["on_start"], %{command: __MODULE__, params: params})

        result = execute_with_tools(interpolate_prompt(@prompt_body, params), @allowed_tools, context)

        emit_signal(@signal_config["emit"]["on_complete"], %{command: __MODULE__, result: result})
        result
      rescue
        error ->
          emit_signal(@signal_config["emit"]["on_error"], %{command: __MODULE__, error: inspect(error)})
          reraise(error, __STACKTRACE__)
      end

      defp emit_signal(nil, _payload), do: :ok

      defp emit_signal(type, payload) do
        {:ok, signal} = Signal.new(type, payload, source: "/commands/#{__MODULE__}")
        Bus.publish(:jido_code_bus, [signal])
      end
    end, Macro.Env.location(__ENV__))

    {:ok, module_name}
  end
end
```

### Hook runner using only signals

```elixir
defmodule JidoCode.Extensibility.HookRunner do
  @moduledoc """
  Subscribes to lifecycle signals and emits configured hook signals.
  """

  alias JidoSignal.Signal
  alias JidoSignal.Bus

  @lifecycle_paths [
    "lifecycle/pre_tool_use",
    "lifecycle/post_tool_use",
    "lifecycle/permission_request",
    "lifecycle/session_start",
    "lifecycle/session_stop",
    "lifecycle/user_prompt_submit",
    "lifecycle/error"
  ]

  def init(hook_config) do
    Enum.each(@lifecycle_paths, fn path ->
      Bus.subscribe(:jido_code_bus, path, dispatch: {:pid, target: self()})
    end)

    %{hooks: normalize_hooks(hook_config)}
  end

  def handle_info({:signal, signal}, state) do
    event = signal.type

    state.hooks
    |> matching_rules(event, signal.data)
    |> Enum.each(fn rule -> emit_rule_signals(rule, signal) end)

    {:noreply, state}
  end

  defp emit_rule_signals(rule, source_signal) do
    Enum.each(rule.emit, fn emission ->
      payload = interpolate_template(emission.data_template, source_signal.data)
      bus = String.to_atom(emission.bus || ":jido_code_bus")

      {:ok, signal} = Signal.new(
        emission.signal_type,
        Map.merge(payload, %{source_signal: source_signal.id}),
        source: "/hooks/#{rule.id}"
      )

      Bus.publish(bus, [signal])
    end)
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
      {JidoCode.Extensibility.HookRunner, [settings_path: ".jido_code/settings.json"]},
      JidoCode.Extensibility.CommandDispatcher
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: JidoCode.Supervisor)
  end
end
```

## Key integration points

- **Commands are the only execution abstraction**: each command is a `Jido.Action` compiled from markdown.
- **Hooks are signal-only**: hook matches emit Jido signals; non-signal hook actions are not supported in this model.
- **Pub/Sub is signal bus-only**: all lifecycle, command, and extension events use `JidoSignal.Bus` path routing.
- **Progressive adoption remains intact**: teams can start with markdown commands, then add richer hook signal policies and packaged extensions.

## Jido v1 to v2 notes for this design

| Aspect | Jido v1 | Jido v2 |
|--------|---------|---------|
| Routing style | Pattern-based (`"extension.**"`) | Path-based (`"extension/loaded"`) |
| Command schema | NimbleOptions | Zoi schemas |
| Signal format | Custom | CloudEvents v1.0.2 |
| Dependencies | Monolithic | Modular (`jido`, `jido_action`, `jido_signal`) |
| Runtime effects | Implicit | Explicit event flow through `JidoSignal.Bus` |
