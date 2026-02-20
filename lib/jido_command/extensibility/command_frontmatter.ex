defmodule JidoCommand.Extensibility.CommandFrontmatter do
  @moduledoc """
  Parses markdown command files with YAML frontmatter into `CommandDefinition` structs.
  """

  alias JidoCommand.Extensibility.CommandDefinition

  @frontmatter_regex ~r/\A---\s*\n(?<frontmatter>.*?)\n---\s*\n(?<body>.*)\z/s

  @allowed_frontmatter_keys [
    "name",
    "description",
    "model",
    "allowed-tools",
    "allowed_tools",
    "jido"
  ]
  @allowed_hook_keys ["pre", "after"]
  @allowed_jido_keys ["command_module", "schema", "hooks"]
  @allowed_schema_option_keys ["type", "required", "doc", "default"]

  @supported_schema_types [:string, :integer, :float, :boolean, :map, :atom, :list]

  @spec parse_file(String.t()) :: {:ok, CommandDefinition.t()} | {:error, term()}
  def parse_file(path) do
    case File.read(path) do
      {:ok, content} -> parse_string(content, path)
      {:error, reason} -> {:error, {:read_error, path, reason}}
    end
  end

  @spec parse_string(String.t(), String.t()) :: {:ok, CommandDefinition.t()} | {:error, term()}
  def parse_string(content, source_path) when is_binary(content) do
    case Regex.named_captures(@frontmatter_regex, content) do
      nil ->
        {:error, {:missing_frontmatter, source_path}}

      %{"frontmatter" => frontmatter_text, "body" => body} ->
        parse_frontmatter_and_build(frontmatter_text, body, source_path)
    end
  rescue
    error -> {:error, {:frontmatter_parse_failed, source_path, error}}
  end

  defp parse_frontmatter_and_build(frontmatter_text, body, source_path) do
    with {:ok, metadata} <- parse_frontmatter_yaml(frontmatter_text, source_path) do
      build_definition(metadata, body, source_path)
    end
  end

  defp parse_frontmatter_yaml(frontmatter_text, source_path) do
    with {:ok, yaml} <- YamlElixir.read_from_string(frontmatter_text),
         true <- is_map(yaml) or {:error, {:invalid_frontmatter, source_path, :root_must_be_map}} do
      {:ok, stringify_keys(yaml)}
    end
  end

  defp build_definition(metadata, body, source_path) do
    with :ok <-
           validate_allowed_keys(metadata, @allowed_frontmatter_keys, :invalid_frontmatter_keys),
         {:ok, name} <- parse_required_nonempty_string(metadata, "name"),
         {:ok, description} <- parse_required_nonempty_string(metadata, "description"),
         {:ok, model} <- parse_optional_string(metadata, "model"),
         {:ok, allowed_tools} <- parse_allowed_tools(metadata),
         {:ok, jido_config} <- parse_jido_config(metadata),
         {:ok, command_module} <- parse_command_module(jido_config),
         {:ok, hooks} <- parse_hooks(jido_config),
         {:ok, schema} <- parse_schema(jido_config) do
      {:ok,
       %CommandDefinition{
         name: name,
         description: description,
         command_module: command_module,
         model: model,
         allowed_tools: allowed_tools,
         schema: schema,
         hooks: hooks,
         body: body,
         source_path: source_path
       }}
    end
  end

  defp parse_required_nonempty_string(metadata, key) do
    case Map.get(metadata, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        if trimmed == "" do
          {:error, {:invalid_frontmatter_field, key, :must_be_nonempty_string}}
        else
          {:ok, trimmed}
        end

      _ ->
        {:error, {:invalid_frontmatter_field, key, :must_be_nonempty_string}}
    end
  end

  defp parse_optional_string(metadata, key) do
    case Map.get(metadata, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        parse_optional_nonempty_string(value, key)

      value when is_atom(value) ->
        value
        |> Atom.to_string()
        |> parse_optional_nonempty_string(key)

      _ ->
        {:error, {:invalid_frontmatter_field, key, :must_be_nonempty_string}}
    end
  end

  defp parse_optional_nonempty_string(value, key) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:error, {:invalid_frontmatter_field, key, :must_be_nonempty_string}}
    else
      {:ok, trimmed}
    end
  end

  defp parse_allowed_tools(metadata) do
    case Map.get(metadata, "allowed-tools") || Map.get(metadata, "allowed_tools") do
      nil ->
        {:ok, []}

      value when is_binary(value) ->
        parse_tools_string(value)

      value when is_list(value) ->
        parse_tools_list(value, length(value))

      _ ->
        {:error, {:invalid_allowed_tools, :must_be_nonempty_string_or_list}}
    end
  end

  defp parse_tools_string(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:error, {:invalid_allowed_tools, :must_be_nonempty_string_or_list}}
    else
      items = String.split(value, ",")
      parse_tools_list(items, length(items))
    end
  end

  defp parse_tools_list(list, source_count) when is_list(list) and is_integer(source_count) do
    list
    |> Enum.reduce_while([], &accumulate_tool/2)
    |> finalize_tools(source_count)
  end

  defp accumulate_tool(item, acc) do
    case normalize_tool(item) do
      {:ok, nil} -> {:cont, acc}
      {:ok, tool} -> {:cont, [tool | acc]}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp finalize_tools({:error, reason}, _source_count), do: {:error, reason}

  defp finalize_tools(tools, source_count) when is_list(tools) and is_integer(source_count) do
    normalized = tools |> Enum.reverse() |> Enum.uniq()

    if normalized == [] do
      {:error, {:invalid_allowed_tools, :must_include_nonempty_tool}}
    else
      {:ok, normalized}
    end
  end

  defp normalize_tool(value) when is_atom(value), do: normalize_tool(Atom.to_string(value))

  defp normalize_tool(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:ok, nil}
    else
      {:ok, trimmed}
    end
  end

  defp normalize_tool(_), do: {:error, {:invalid_allowed_tools, :items_must_be_strings_or_atoms}}

  defp parse_jido_config(metadata) do
    case Map.get(metadata, "jido") do
      nil ->
        {:ok, %{}}

      jido when is_map(jido) ->
        normalized = normalize_map(jido)
        unknown_keys = normalized |> Map.keys() |> Enum.reject(&(&1 in @allowed_jido_keys))

        if unknown_keys == [] do
          {:ok, normalized}
        else
          {:error, {:invalid_jido_keys, unknown_keys}}
        end

      _ ->
        {:error, {:invalid_jido, :must_be_map}}
    end
  end

  defp parse_command_module(jido_config) do
    case Map.get(jido_config, "command_module") do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        module_name = String.trim(value)

        cond do
          module_name == "" ->
            {:error, {:invalid_command_module, :must_be_nonempty_string}}

          valid_module_name?(module_name) ->
            {:ok, Module.concat([module_name])}

          true ->
            {:error, {:invalid_command_module, :invalid_format}}
        end

      _ ->
        {:error, {:invalid_command_module, :must_be_string}}
    end
  end

  defp valid_module_name?(module_name) do
    Regex.match?(~r/^([A-Z][A-Za-z0-9_]*)(\.[A-Z][A-Za-z0-9_]*)*$/, module_name)
  end

  defp parse_hooks(jido_config) do
    case Map.get(jido_config, "hooks") do
      nil ->
        {:ok, %{pre: false, after: false}}

      hooks when is_map(hooks) ->
        hooks
        |> normalize_map()
        |> parse_hooks_map()

      _ ->
        {:error, {:invalid_hooks, :must_be_map}}
    end
  end

  defp parse_hooks_map(hooks) do
    with :ok <- validate_allowed_keys(hooks, @allowed_hook_keys, :invalid_hooks),
         {:ok, pre_enabled} <- validate_hook_value("pre", Map.get(hooks, "pre")),
         {:ok, after_enabled} <- validate_hook_value("after", Map.get(hooks, "after")) do
      {:ok, %{pre: pre_enabled, after: after_enabled}}
    end
  end

  defp validate_hook_value(_hook_name, nil), do: {:ok, false}
  defp validate_hook_value(_hook_name, value) when is_boolean(value), do: {:ok, value}

  defp validate_hook_value(hook_name, _value) do
    {:error, {:invalid_hook_value, hook_name, :must_be_boolean_or_nil}}
  end

  defp parse_schema(jido_config) do
    schema = Map.get(jido_config, "schema")

    case schema do
      nil ->
        {:ok, []}

      map when is_map(map) ->
        parse_schema_map(map)

      _ ->
        {:error, {:invalid_schema, :expected_map}}
    end
  end

  defp parse_schema_map(map) do
    map
    |> Enum.sort_by(fn {field, _} -> to_string(field) end)
    |> Enum.reduce_while([], &accumulate_schema_entry/2)
    |> finalize_schema_entries()
  end

  defp accumulate_schema_entry({field, spec}, acc) do
    case parse_schema_entry(field, spec) do
      {:ok, entry} -> {:cont, [entry | acc]}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp finalize_schema_entries({:error, reason}), do: {:error, reason}
  defp finalize_schema_entries(entries), do: {:ok, Enum.reverse(entries)}

  defp parse_schema_entry(field, spec) when is_map(spec) do
    field_name = field |> to_string() |> String.trim()

    with :ok <- validate_schema_field_name(field_name),
         {:ok, spec_map} <- normalize_schema_spec(field_name, spec),
         {:ok, type} <- parse_schema_type(field_name, spec_map),
         {:ok, required} <- parse_schema_required(field_name, spec_map),
         {:ok, doc} <- parse_schema_doc(field_name, spec_map),
         {:ok, default} <- parse_schema_default(spec_map),
         :ok <- validate_required_default(field_name, required, default),
         :ok <- validate_default_type(field_name, type, default) do
      normalized_default = normalize_schema_default(type, default)
      opts = [type: type, required: required]
      opts = if is_binary(doc), do: Keyword.put(opts, :doc, doc), else: opts

      opts =
        if normalized_default == :__missing__ do
          opts
        else
          Keyword.put(opts, :default, normalized_default)
        end

      {:ok, {String.to_atom(field_name), opts}}
    end
  end

  defp parse_schema_entry(field, _spec), do: {:error, {:invalid_schema_entry, field}}

  defp validate_schema_field_name("") do
    {:error, {:invalid_schema_field, :empty}}
  end

  defp validate_schema_field_name(field_name) do
    if Regex.match?(~r/^[a-z][a-zA-Z0-9_]*$/, field_name) do
      :ok
    else
      {:error, {:invalid_schema_field, field_name}}
    end
  end

  defp normalize_schema_spec(field_name, spec) do
    normalized = normalize_map(spec)

    case validate_allowed_keys(normalized, @allowed_schema_option_keys, :invalid_schema_options) do
      :ok ->
        {:ok, normalized}

      {:error, {:invalid_schema_options, {:unknown_keys, unknown_keys}}} ->
        {:error, {:invalid_schema_options, field_name, unknown_keys}}
    end
  end

  defp parse_schema_type(field_name, spec_map) do
    type =
      spec_map
      |> Map.get("type", "string")
      |> to_type_atom()

    if type in @supported_schema_types do
      {:ok, type}
    else
      {:error, {:invalid_schema_type, field_name, type}}
    end
  end

  defp parse_schema_required(field_name, spec_map) do
    case Map.get(spec_map, "required", false) do
      value when is_boolean(value) -> {:ok, value}
      _ -> {:error, {:invalid_schema_required, field_name}}
    end
  end

  defp parse_schema_doc(_field_name, spec_map) do
    case Map.get(spec_map, "doc") do
      nil -> {:ok, nil}
      value when is_binary(value) -> {:ok, String.trim(value)}
      _ -> {:error, {:invalid_schema_doc, :must_be_string}}
    end
  end

  defp parse_schema_default(spec_map) do
    if Map.has_key?(spec_map, "default") do
      {:ok, Map.get(spec_map, "default")}
    else
      {:ok, :__missing__}
    end
  end

  defp validate_required_default(field_name, true, default) when default != :__missing__ do
    {:error, {:invalid_schema_default, field_name, :required_cannot_define_default}}
  end

  defp validate_required_default(_field_name, _required, _default), do: :ok

  defp validate_default_type(_field_name, _type, :__missing__), do: :ok

  defp validate_default_type(_field_name, :string, default) when is_binary(default), do: :ok
  defp validate_default_type(_field_name, :integer, default) when is_integer(default), do: :ok
  defp validate_default_type(_field_name, :float, default) when is_float(default), do: :ok
  defp validate_default_type(_field_name, :float, default) when is_integer(default), do: :ok
  defp validate_default_type(_field_name, :boolean, default) when is_boolean(default), do: :ok
  defp validate_default_type(_field_name, :map, default) when is_map(default), do: :ok
  defp validate_default_type(_field_name, :list, default) when is_list(default), do: :ok
  defp validate_default_type(_field_name, :atom, default) when is_atom(default), do: :ok

  defp validate_default_type(field_name, :atom, default) when is_binary(default) do
    if valid_atom_literal?(default) do
      :ok
    else
      {:error, {:invalid_schema_default_type, field_name, :atom}}
    end
  end

  defp validate_default_type(field_name, type, _default) do
    {:error, {:invalid_schema_default_type, field_name, type}}
  end

  defp normalize_schema_default(:atom, default) when is_binary(default) do
    default
    |> String.trim()
    |> String.to_atom()
  end

  defp normalize_schema_default(_type, default), do: default

  defp valid_atom_literal?(value) when is_binary(value) do
    Regex.match?(~r/^[a-z][a-zA-Z0-9_]*$/, String.trim(value))
  end

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

  defp validate_allowed_keys(map, allowed_keys, error_tag) do
    unknown_keys =
      map
      |> Map.keys()
      |> Enum.reject(&(&1 in allowed_keys))
      |> Enum.sort()

    if unknown_keys == [] do
      :ok
    else
      {:error, {error_tag, {:unknown_keys, unknown_keys}}}
    end
  end

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), stringify_keys(value)} end)
    |> Map.new()
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
