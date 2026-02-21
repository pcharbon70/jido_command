defmodule JidoCommand.Config.Settings do
  @moduledoc """
  Normalized runtime settings loaded from global and local `settings.json` files.
  """

  @allowed_settings_keys ["$schema", "version", "signal_bus", "permissions", "commands"]
  @allowed_signal_bus_keys ["name", "middleware"]
  @allowed_middleware_keys ["module", "opts"]
  @allowed_middleware_option_keys ["level"]
  @allowed_permissions_keys ["allow", "deny", "ask"]
  @allowed_commands_keys ["default_model", "max_concurrent"]

  @type t :: %__MODULE__{
          bus_name: atom(),
          bus_middleware: [{module(), keyword()}],
          commands_default_model: String.t() | nil,
          commands_max_concurrent: pos_integer(),
          permissions_allow: [String.t()],
          permissions_deny: [String.t()],
          permissions_ask: [String.t()]
        }

  defstruct bus_name: :jido_code_bus,
            bus_middleware: [{Jido.Signal.Bus.Middleware.Logger, level: :debug}],
            commands_default_model: nil,
            commands_max_concurrent: 5,
            permissions_allow: [],
            permissions_deny: [],
            permissions_ask: []

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    normalized_map = normalize_map_keys(map)

    signal_bus = Map.get(normalized_map, "signal_bus", %{})
    commands = Map.get(normalized_map, "commands", %{})
    permissions = Map.get(normalized_map, "permissions", %{})

    %__MODULE__{
      bus_name: to_bus_name(Map.get(signal_bus, "name", ":jido_code_bus")),
      bus_middleware: parse_middleware(Map.get(signal_bus, "middleware", [])),
      commands_default_model: parse_default_model(Map.get(commands, "default_model")),
      commands_max_concurrent: to_positive_integer(Map.get(commands, "max_concurrent", 5), 5),
      permissions_allow: parse_permissions(permissions, "allow"),
      permissions_deny: parse_permissions(permissions, "deny"),
      permissions_ask: parse_permissions(permissions, "ask")
    }
  end

  @spec validate(map()) :: :ok | {:error, term()}
  def validate(map) when is_map(map) do
    :ok
    |> chain_validate(fn ->
      validate_allowed_keys(map, @allowed_settings_keys, :invalid_settings_keys)
    end)
    |> chain_validate(fn -> validate_schema_url(settings_get(map, "$schema")) end)
    |> chain_validate(fn -> validate_version(settings_get(map, "version")) end)
    |> chain_validate(fn -> validate_signal_bus(settings_get(map, "signal_bus")) end)
    |> chain_validate(fn -> validate_permissions(settings_get(map, "permissions")) end)
    |> chain_validate(fn -> validate_commands(settings_get(map, "commands")) end)
  end

  def validate(_), do: {:error, {:invalid_settings, :root_must_be_map}}

  @spec bus_opts(t()) :: keyword()
  def bus_opts(%__MODULE__{} = settings) do
    [
      name: settings.bus_name,
      middleware: settings.bus_middleware
    ]
  end

  @spec permissions(t()) :: %{allow: [String.t()], deny: [String.t()], ask: [String.t()]}
  def permissions(%__MODULE__{} = settings) do
    %{
      allow: settings.permissions_allow,
      deny: settings.permissions_deny,
      ask: settings.permissions_ask
    }
  end

  defp to_bus_name(name) when is_atom(name), do: name

  defp to_bus_name(name) when is_binary(name) do
    normalized =
      name
      |> String.trim()
      |> String.trim_leading(":")

    if normalized == "" do
      :jido_code_bus
    else
      String.to_atom(normalized)
    end
  end

  defp to_bus_name(_), do: :jido_code_bus

  defp parse_middleware(middleware) when is_list(middleware) do
    parsed =
      Enum.flat_map(middleware, fn item ->
        case parse_middleware_item(item) do
          nil -> []
          tuple -> [tuple]
        end
      end)

    if parsed == [] do
      [{Jido.Signal.Bus.Middleware.Logger, level: :debug}]
    else
      parsed
    end
  end

  defp parse_middleware(_), do: [{Jido.Signal.Bus.Middleware.Logger, level: :debug}]

  defp parse_middleware_item(%{"module" => "Jido.Signal.Bus.Middleware.Logger"} = item) do
    opts = map_to_keyword(Map.get(item, "opts", %{}))
    {Jido.Signal.Bus.Middleware.Logger, opts}
  end

  defp parse_middleware_item(_), do: nil

  defp map_to_keyword(map) when is_map(map) do
    map
    |> Enum.reduce([], fn
      {"level", level}, acc -> [{:level, maybe_to_atom(level)} | acc]
      {_k, _v}, acc -> acc
    end)
    |> Enum.reverse()
  end

  defp map_to_keyword(_), do: []

  defp maybe_to_atom(value) when is_atom(value), do: value

  defp maybe_to_atom(value) when is_binary(value) do
    case value do
      "debug" -> :debug
      "info" -> :info
      "warn" -> :warning
      "warning" -> :warning
      "error" -> :error
      _ -> :info
    end
  end

  defp maybe_to_atom(_), do: :info

  defp to_positive_integer(value, _fallback) when is_integer(value) and value > 0, do: value
  defp to_positive_integer(_, fallback), do: fallback

  defp parse_default_model(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp parse_default_model(_), do: nil

  defp parse_permissions(permissions, key) when is_map(permissions) and is_binary(key) do
    permissions
    |> Map.get(key, [])
    |> to_permission_list()
    |> Enum.reduce([], fn item, acc ->
      case normalize_permission(item) do
        nil -> acc
        permission -> [permission | acc]
      end
    end)
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp parse_permissions(_permissions, _key), do: []

  defp to_permission_list(value) when is_list(value), do: value

  defp to_permission_list(value) when is_binary(value) do
    String.split(value, ",")
  end

  defp to_permission_list(_), do: []

  defp normalize_permission(value) when is_atom(value),
    do: normalize_permission(Atom.to_string(value))

  defp normalize_permission(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_permission(_), do: nil

  defp validate_signal_bus(nil), do: :ok

  defp validate_signal_bus(signal_bus) when is_map(signal_bus) do
    :ok
    |> chain_validate(fn ->
      validate_allowed_keys(signal_bus, @allowed_signal_bus_keys, :invalid_signal_bus_keys)
    end)
    |> chain_validate(fn -> validate_signal_bus_name(settings_get(signal_bus, "name")) end)
    |> chain_validate(fn ->
      validate_signal_bus_middleware(settings_get(signal_bus, "middleware"))
    end)
  end

  defp validate_signal_bus(_), do: {:error, {:invalid_signal_bus, :must_be_map}}

  defp validate_signal_bus_middleware(nil), do: :ok

  defp validate_signal_bus_middleware(middleware) when is_list(middleware) do
    middleware
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {item, index}, :ok ->
      case validate_middleware_item(item) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:invalid_signal_bus_middleware, index, reason}}}
      end
    end)
  end

  defp validate_signal_bus_middleware(_),
    do: {:error, {:invalid_signal_bus_middleware, :must_be_list}}

  defp validate_middleware_item(item) when is_map(item) do
    :ok
    |> chain_validate(fn ->
      validate_allowed_keys(item, @allowed_middleware_keys, :invalid_middleware_keys)
    end)
    |> chain_validate(fn -> validate_middleware_module(settings_get(item, "module")) end)
    |> chain_validate(fn -> validate_middleware_opts(settings_get(item, "opts")) end)
  end

  defp validate_middleware_item(_), do: {:error, :item_must_be_map}

  defp validate_middleware_module("Jido.Signal.Bus.Middleware.Logger"), do: :ok
  defp validate_middleware_module(Jido.Signal.Bus.Middleware.Logger), do: :ok
  defp validate_middleware_module(nil), do: {:error, :module_is_required}
  defp validate_middleware_module(_), do: {:error, :unsupported_module}

  defp validate_middleware_opts(nil), do: :ok

  defp validate_middleware_opts(opts) when is_map(opts) do
    :ok
    |> chain_validate(fn ->
      validate_allowed_keys(opts, @allowed_middleware_option_keys, :invalid_middleware_opts_keys)
    end)
    |> chain_validate(fn -> validate_middleware_level(settings_get(opts, "level")) end)
  end

  defp validate_middleware_opts(_), do: {:error, :opts_must_be_map}

  defp validate_middleware_level(nil), do: :ok
  defp validate_middleware_level(:debug), do: :ok
  defp validate_middleware_level(:info), do: :ok
  defp validate_middleware_level(:warn), do: :ok
  defp validate_middleware_level(:warning), do: :ok
  defp validate_middleware_level(:error), do: :ok
  defp validate_middleware_level("debug"), do: :ok
  defp validate_middleware_level("info"), do: :ok
  defp validate_middleware_level("warn"), do: :ok
  defp validate_middleware_level("warning"), do: :ok
  defp validate_middleware_level("error"), do: :ok
  defp validate_middleware_level(_), do: {:error, :invalid_level}

  defp validate_permissions(nil), do: :ok

  defp validate_permissions(permissions) when is_map(permissions) do
    :ok
    |> chain_validate(fn ->
      validate_allowed_keys(permissions, @allowed_permissions_keys, :invalid_permissions_keys)
    end)
    |> chain_validate(fn -> validate_permission_entries(permissions) end)
  end

  defp validate_permissions(_), do: {:error, {:invalid_permissions, :must_be_map}}

  defp validate_permission_entries(permissions) when is_map(permissions) do
    Enum.reduce_while(@allowed_permissions_keys, :ok, fn key, :ok ->
      case validate_permission_value(settings_get(permissions, key), key) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_permission_value(nil, _key), do: :ok
  defp validate_permission_value(value, _key) when is_binary(value), do: :ok

  defp validate_permission_value(value, key) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {item, index}, :ok ->
      if is_binary(item) or is_atom(item) do
        {:cont, :ok}
      else
        {:halt, {:error, {:invalid_permission_item, key, index}}}
      end
    end)
  end

  defp validate_permission_value(_value, key),
    do: {:error, {:invalid_permission_value, key, :must_be_string_or_list}}

  defp validate_commands(nil), do: :ok

  defp validate_commands(commands) when is_map(commands) do
    :ok
    |> chain_validate(fn ->
      validate_allowed_keys(commands, @allowed_commands_keys, :invalid_commands_keys)
    end)
    |> chain_validate(fn -> validate_default_model(settings_get(commands, "default_model")) end)
    |> chain_validate(fn -> validate_max_concurrent(settings_get(commands, "max_concurrent")) end)
  end

  defp validate_commands(_), do: {:error, {:invalid_commands, :must_be_map}}

  defp validate_default_model(nil), do: :ok

  defp validate_default_model(model) when is_binary(model) do
    if String.trim(model) == "" do
      {:error, {:invalid_default_model, :must_be_nonempty_string}}
    else
      :ok
    end
  end

  defp validate_default_model(_), do: {:error, {:invalid_default_model, :must_be_nonempty_string}}

  defp validate_max_concurrent(nil), do: :ok
  defp validate_max_concurrent(value) when is_integer(value) and value > 0, do: :ok

  defp validate_max_concurrent(_),
    do: {:error, {:invalid_max_concurrent, :must_be_positive_integer}}

  defp validate_schema_url(nil), do: :ok

  defp validate_schema_url(value) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, {:invalid_schema_url, :must_be_nonempty_string}}
    else
      :ok
    end
  end

  defp validate_schema_url(_), do: {:error, {:invalid_schema_url, :must_be_nonempty_string}}

  defp validate_version(nil), do: :ok

  defp validate_version(value) when is_binary(value) do
    if Regex.match?(~r/^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/, String.trim(value)) do
      :ok
    else
      {:error, {:invalid_version, :must_be_semver}}
    end
  end

  defp validate_version(_), do: {:error, {:invalid_version, :must_be_semver}}

  defp validate_signal_bus_name(nil), do: :ok
  defp validate_signal_bus_name(value) when is_atom(value), do: :ok

  defp validate_signal_bus_name(value) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, {:invalid_signal_bus_name, :must_be_nonempty_string_or_atom}}
    else
      :ok
    end
  end

  defp validate_signal_bus_name(_),
    do: {:error, {:invalid_signal_bus_name, :must_be_nonempty_string_or_atom}}

  defp validate_allowed_keys(map, allowed_keys, tag) when is_map(map) do
    normalized_keys =
      map
      |> Map.keys()
      |> Enum.map(&normalize_settings_key/1)

    conflicting_keys =
      normalized_keys
      |> Enum.frequencies()
      |> Enum.reduce([], fn
        {key, count}, acc when count > 1 -> [key | acc]
        {_key, _count}, acc -> acc
      end)
      |> Enum.sort()

    unknown_keys =
      normalized_keys
      |> Enum.reject(&(&1 in allowed_keys))
      |> Enum.sort()

    cond do
      conflicting_keys != [] ->
        {:error, {tag, {:conflicting_keys, conflicting_keys}}}

      unknown_keys != [] ->
        {:error, {tag, {:unknown_keys, unknown_keys}}}

      true ->
        :ok
    end
  end

  defp normalize_settings_key(key) when is_binary(key), do: key
  defp normalize_settings_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_settings_key(key), do: inspect(key)

  defp normalize_map_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      Map.put(acc, normalize_settings_key(key), normalize_map_keys(value))
    end)
  end

  defp normalize_map_keys(list) when is_list(list),
    do: Enum.map(list, &normalize_map_keys/1)

  defp normalize_map_keys(value), do: value

  defp settings_get(map, key, default \\ nil) when is_map(map) and is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        case safe_existing_atom(key) do
          nil -> default
          atom_key -> Map.get(map, atom_key, default)
        end
    end
  end

  defp safe_existing_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp chain_validate(:ok, validation), do: validation.()
  defp chain_validate({:error, _reason} = error, _validation), do: error
end
