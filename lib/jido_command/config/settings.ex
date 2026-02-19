defmodule JidoCommand.Config.Settings do
  @moduledoc """
  Normalized runtime settings loaded from global and local `settings.json` files.
  """

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
    signal_bus = Map.get(map, "signal_bus", %{})
    commands = Map.get(map, "commands", %{})
    permissions = Map.get(map, "permissions", %{})

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

  defp parse_default_model(value) when is_binary(value), do: value
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
end
