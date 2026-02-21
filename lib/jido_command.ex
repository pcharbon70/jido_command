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
  def invoke(name, params \\ %{}, context \\ %{}, opts \\ []) do
    registry = Keyword.get(opts, :registry, CommandRegistry)
    bus = Keyword.get(opts, :bus, :jido_code_bus)
    invocation_id_option = Keyword.get(opts, :invocation_id)

    permissions = normalize_permissions(Keyword.get(opts, :permissions))

    with {:ok, normalized_name} <- validate_command_name(name),
         :ok <- validate_map_arg(params, :invalid_params),
         :ok <- validate_map_arg(context, :invalid_context),
         :ok <- validate_context_invocation_id_keys(context),
         {:ok, module} <- CommandRegistry.get_command(normalized_name, registry) do
      invocation_id = resolve_invocation_id(context, invocation_id_option)

      run_context =
        context
        |> Map.put_new(:bus, bus)
        |> put_invocation_id(invocation_id)
        |> maybe_put_permissions(permissions)

      Jido.Exec.run(module, params, run_context)
    end
  end

  @spec dispatch(String.t(), map(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def dispatch(name, params \\ %{}, context \\ %{}, opts \\ []) do
    bus = Keyword.get(opts, :bus, :jido_code_bus)
    invocation_id_option = Keyword.get(opts, :invocation_id)

    with {:ok, normalized_name} <- validate_command_name(name),
         :ok <- validate_map_arg(params, :invalid_params),
         :ok <- validate_map_arg(context, :invalid_context),
         :ok <- validate_context_invocation_id_keys(context) do
      invocation_id = resolve_invocation_id(context, invocation_id_option)

      with {:ok, signal} <-
             Signal.new(
               "command.invoke",
               %{
                 "name" => normalized_name,
                 "params" => params,
                 "context" => context,
                 "invocation_id" => invocation_id
               },
               source: "/jido_command"
             ),
           {:ok, _recorded} <- Bus.publish(bus, [signal]) do
        {:ok, invocation_id}
      end
    end
  end

  @spec reload(keyword()) :: :ok | {:error, term()}
  def reload(opts \\ []) do
    registry = Keyword.get(opts, :registry, CommandRegistry)
    CommandRegistry.reload(registry)
  end

  @spec register_command(String.t(), keyword()) :: :ok | {:error, term()}
  def register_command(command_path, opts \\ []) do
    registry = Keyword.get(opts, :registry, CommandRegistry)

    with {:ok, normalized_path} <- validate_nonempty_string(command_path, :invalid_path) do
      CommandRegistry.register_command(normalized_path, registry)
    end
  end

  @spec unregister_command(String.t(), keyword()) :: :ok | {:error, term()}
  def unregister_command(command_name, opts \\ []) do
    registry = Keyword.get(opts, :registry, CommandRegistry)

    with {:ok, normalized_name} <- validate_nonempty_string(command_name, :invalid_name) do
      CommandRegistry.unregister_command(normalized_name, registry)
    end
  end

  defp default_invocation_id do
    Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end

  defp put_invocation_id(context, invocation_id) when is_map(context) do
    context
    |> Map.delete("invocation_id")
    |> Map.put(:invocation_id, invocation_id)
  end

  defp maybe_put_permissions(context, nil), do: context

  defp maybe_put_permissions(context, permissions),
    do: Map.put(context, :permissions, permissions)

  defp validate_command_name(value), do: validate_nonempty_string(value, :invalid_name)

  defp validate_nonempty_string(value, error_tag) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:error, error_tag}
    else
      {:ok, trimmed}
    end
  end

  defp validate_nonempty_string(_value, error_tag), do: {:error, error_tag}

  defp validate_map_arg(value, _error_tag) when is_map(value), do: :ok
  defp validate_map_arg(_value, error_tag), do: {:error, error_tag}

  defp validate_context_invocation_id_keys(context) when is_map(context) do
    if Map.has_key?(context, :invocation_id) and Map.has_key?(context, "invocation_id") do
      {:error, :conflicting_context_invocation_id_keys}
    else
      :ok
    end
  end

  defp resolve_invocation_id(context, invocation_id_option) when is_map(context) do
    option_invocation_id = normalize_invocation_id(invocation_id_option, nil)
    context_invocation_id = normalize_invocation_id(raw_context_invocation_id(context), nil)

    option_invocation_id || context_invocation_id || default_invocation_id()
  end

  defp raw_context_invocation_id(context) when is_map(context) do
    case Map.fetch(context, :invocation_id) do
      {:ok, value} -> value
      :error -> Map.get(context, "invocation_id")
    end
  end

  defp normalize_invocation_id(value, fallback) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: fallback, else: trimmed
  end

  defp normalize_invocation_id(_value, fallback), do: fallback

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
