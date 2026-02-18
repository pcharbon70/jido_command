defmodule JidoCommand.Extensibility.CommandFrontmatter do
  @moduledoc """
  Parses markdown command files with YAML frontmatter into `CommandDefinition` structs.
  """

  alias JidoCommand.Extensibility.CommandDefinition

  @frontmatter_regex ~r/\A---\s*\n(?<frontmatter>.*?)\n---\s*\n(?<body>.*)\z/s
  @allowed_hook_keys ["pre", "after"]

  @spec parse_file(String.t()) :: {:ok, CommandDefinition.t()} | {:error, term()}
  def parse_file(path) do
    with {:ok, content} <- File.read(path) do
      parse_string(content, path)
    end
  end

  @spec parse_string(String.t(), String.t()) :: {:ok, CommandDefinition.t()} | {:error, term()}
  def parse_string(content, source_path) when is_binary(content) do
    case Regex.named_captures(@frontmatter_regex, content) do
      nil ->
        {:error, {:missing_frontmatter, source_path}}

      %{"frontmatter" => frontmatter_text, "body" => body} ->
        with {:ok, yaml} <- YamlElixir.read_from_string(frontmatter_text),
             metadata <- stringify_keys(yaml),
             {:ok, hooks} <- parse_hooks(metadata),
             {:ok, schema} <- parse_schema(metadata),
             {:ok, allowed_tools} <- parse_allowed_tools(metadata) do
          {:ok,
           %CommandDefinition{
             name: parse_name(metadata, source_path),
             description: parse_description(metadata),
             model: parse_model(metadata),
             allowed_tools: allowed_tools,
             schema: schema,
             hooks: hooks,
             body: body,
             source_path: source_path
           }}
        end
    end
  rescue
    error -> {:error, {:frontmatter_parse_failed, source_path, error}}
  end

  defp parse_name(metadata, source_path) do
    metadata
    |> Map.get("name", Path.basename(source_path, ".md"))
    |> to_string()
  end

  defp parse_description(metadata) do
    metadata
    |> Map.get("description", "")
    |> to_string()
  end

  defp parse_model(metadata) do
    case Map.get(metadata, "model") do
      value when is_binary(value) -> value
      value when is_atom(value) -> Atom.to_string(value)
      _ -> nil
    end
  end

  defp parse_allowed_tools(metadata) do
    case Map.get(metadata, "allowed-tools") || Map.get(metadata, "allowed_tools") do
      nil -> {:ok, []}
      value when is_binary(value) -> {:ok, split_csv(value)}
      value when is_list(value) -> {:ok, Enum.map(value, &to_string/1)}
      _ -> {:error, {:invalid_allowed_tools, :expected_string_or_list}}
    end
  end

  defp split_csv(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_hooks(metadata) do
    hooks = metadata |> get_in(["jido", "hooks"]) |> normalize_map()

    unknown_keys = hooks |> Map.keys() |> Enum.reject(&(&1 in @allowed_hook_keys))

    if unknown_keys != [] do
      {:error, {:invalid_hooks, {:unknown_keys, unknown_keys}}}
    else
      with {:ok, pre_hook} <- validate_hook_value(Map.get(hooks, "pre")),
           {:ok, after_hook} <- validate_hook_value(Map.get(hooks, "after")) do
        {:ok, %{pre: pre_hook, after: after_hook}}
      end
    end
  end

  defp validate_hook_value(nil), do: {:ok, nil}
  defp validate_hook_value(value) when is_binary(value), do: {:ok, value}
  defp validate_hook_value(_), do: {:error, {:invalid_hook_value, :expected_string_or_nil}}

  defp parse_schema(metadata) do
    schema = metadata |> get_in(["jido", "schema"])

    case schema do
      nil ->
        {:ok, []}

      map when is_map(map) ->
        map
        |> Enum.reduce_while({:ok, []}, fn {field, spec}, {:ok, acc} ->
          with {:ok, entry} <- parse_schema_entry(field, spec) do
            {:cont, {:ok, [entry | acc]}}
          end
        end)
        |> case do
          {:ok, entries} -> {:ok, Enum.reverse(entries)}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, {:invalid_schema, :expected_map}}
    end
  end

  defp parse_schema_entry(field, spec) when is_map(spec) do
    field_atom = String.to_atom(to_string(field))

    type =
      spec
      |> Map.get("type", "string")
      |> to_type_atom()

    if type == :unsupported do
      {:error, {:invalid_schema_type, field}}
    else
      required = Map.get(spec, "required", false) == true
      doc = Map.get(spec, "doc")

      opts = [type: type, required: required]
      opts = if is_binary(doc), do: Keyword.put(opts, :doc, doc), else: opts

      {:ok, {field_atom, opts}}
    end
  end

  defp parse_schema_entry(field, _spec), do: {:error, {:invalid_schema_entry, field}}

  defp to_type_atom(value) when is_atom(value), do: value

  defp to_type_atom(value) when is_binary(value) do
    case String.downcase(value) do
      "string" -> :string
      "integer" -> :integer
      "float" -> :float
      "boolean" -> :boolean
      "map" -> :map
      "atom" -> :atom
      "list" -> :list
      _ -> :unsupported
    end
  end

  defp to_type_atom(_), do: :unsupported

  defp normalize_map(map) when is_map(map), do: stringify_keys(map)
  defp normalize_map(_), do: %{}

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), stringify_keys(value)} end)
    |> Map.new()
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
