defmodule JidoCommand.Extensibility.Command do
  @moduledoc """
  Compiles markdown command definitions into runtime `Jido.Action` modules.
  """

  alias JidoCommand.Extensibility.CommandDefinition
  alias JidoCommand.Extensibility.CommandFrontmatter

  @type compiled_command :: %{
          name: String.t(),
          module: module(),
          definition: CommandDefinition.t()
        }

  @spec from_markdown(String.t()) :: {:ok, compiled_command()} | {:error, term()}
  def from_markdown(path) do
    with {:ok, definition} <- CommandFrontmatter.parse_file(path),
         {:ok, module_name} <- compile(definition) do
      {:ok, %{name: definition.name, module: module_name, definition: definition}}
    end
  end

  @spec compile(CommandDefinition.t()) :: {:ok, module()} | {:error, term()}
  def compile(%CommandDefinition{} = definition) do
    module_name = module_name_from_definition(definition)

    schema = definition.schema
    escaped_definition = Macro.escape(definition)
    action_name = normalize_action_name(definition.name)
    description = definition.description

    purge_module(module_name)

    quoted =
      quote location: :keep do
        use Jido.Action,
          name: unquote(action_name),
          description: unquote(description),
          schema: unquote(schema)

        @command_definition unquote(escaped_definition)

        @impl true
        def run(params, context) do
          JidoCommand.Extensibility.CommandRuntime.execute(@command_definition, params, context)
        end
      end

    case Module.create(module_name, quoted, Macro.Env.location(__ENV__)) do
      {:module, ^module_name, _binary, _exports} -> {:ok, module_name}
      other -> {:error, {:module_create_failed, other}}
    end
  end

  defp normalize_action_name(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]+/, "_")
    |> String.trim("_")
    |> case do
      "" -> "command"
      normalized -> normalized
    end
  end

  defp module_name_from_definition(%CommandDefinition{name: name, source_path: source_path}) do
    digest =
      :crypto.hash(:sha256, "#{source_path}:#{name}")
      |> Base.encode16(case: :lower)
      |> binary_part(0, 10)

    normalized =
      name
      |> String.replace(~r/[^a-zA-Z0-9_]+/, "_")
      |> Macro.camelize()

    Module.concat([JidoCommand, DynamicCommands, normalized <> "_" <> digest])
  end

  defp purge_module(module) do
    if Code.ensure_loaded?(module) do
      :code.purge(module)
      :code.delete(module)
    end

    :ok
  end
end
