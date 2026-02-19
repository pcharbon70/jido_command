defmodule JidoCommand do
  @moduledoc """
  Public API for invoking and dispatching markdown-defined Jido commands.
  """

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoCommand.Extensibility.CommandRegistry

  @spec list_commands(keyword()) :: [String.t()]
  def list_commands(opts \\ []) do
    registry = Keyword.get(opts, :registry, CommandRegistry)
    CommandRegistry.list_commands(registry)
  end

  @spec invoke(String.t(), map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def invoke(name, params \\ %{}, context \\ %{}, opts \\ []) when is_binary(name) do
    registry = Keyword.get(opts, :registry, CommandRegistry)
    bus = Keyword.get(opts, :bus, :jido_code_bus)
    invocation_id = Keyword.get(opts, :invocation_id, default_invocation_id())
    permissions = normalize_permissions(Keyword.get(opts, :permissions))

    with {:ok, module} <- CommandRegistry.get_command(name, registry) do
      run_context =
        context
        |> Map.put_new(:bus, bus)
        |> Map.put_new(:invocation_id, invocation_id)
        |> maybe_put_permissions(permissions)

      Jido.Exec.run(module, params, run_context)
    end
  end

  @spec dispatch(String.t(), map(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def dispatch(name, params \\ %{}, context \\ %{}, opts \\ []) when is_binary(name) do
    bus = Keyword.get(opts, :bus, :jido_code_bus)
    invocation_id = Keyword.get(opts, :invocation_id, default_invocation_id())

    payload = %{
      "name" => name,
      "params" => params,
      "context" => context,
      "invocation_id" => invocation_id
    }

    with {:ok, signal} <- Signal.new("command.invoke", payload, source: "/jido_command"),
         {:ok, _recorded} <- Bus.publish(bus, [signal]) do
      {:ok, invocation_id}
    end
  end

  @spec reload(keyword()) :: :ok | {:error, term()}
  def reload(opts \\ []) do
    registry = Keyword.get(opts, :registry, CommandRegistry)
    CommandRegistry.reload(registry)
  end

  @spec register_command(String.t(), keyword()) :: :ok | {:error, term()}
  def register_command(command_path, opts \\ []) when is_binary(command_path) do
    registry = Keyword.get(opts, :registry, CommandRegistry)
    CommandRegistry.register_command(command_path, registry)
  end

  @spec unregister_command(String.t(), keyword()) :: :ok | {:error, term()}
  def unregister_command(command_name, opts \\ []) when is_binary(command_name) do
    registry = Keyword.get(opts, :registry, CommandRegistry)
    CommandRegistry.unregister_command(command_name, registry)
  end

  defp default_invocation_id do
    Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end

  defp maybe_put_permissions(context, nil), do: context

  defp maybe_put_permissions(context, permissions),
    do: Map.put(context, :permissions, permissions)

  defp normalize_permissions(value) when is_map(value) do
    %{
      allow: normalize_permission_list(Map.get(value, :allow) || Map.get(value, "allow")),
      deny: normalize_permission_list(Map.get(value, :deny) || Map.get(value, "deny")),
      ask: normalize_permission_list(Map.get(value, :ask) || Map.get(value, "ask"))
    }
  end

  defp normalize_permissions(_), do: nil

  defp normalize_permission_list(list) when is_list(list) do
    list
    |> Enum.reduce([], fn permission, acc ->
      case normalize_permission(permission) do
        nil -> acc
        normalized -> [normalized | acc]
      end
    end)
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp normalize_permission_list(_), do: []

  defp normalize_permission(value) when is_atom(value),
    do: normalize_permission(Atom.to_string(value))

  defp normalize_permission(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_permission(_), do: nil
end
