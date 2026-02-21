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
    permissions_option = Keyword.get(opts, :permissions)

    with {:ok, normalized_name} <- validate_command_name(name),
         :ok <- validate_map_arg(params, :invalid_params),
         :ok <- validate_map_arg(context, :invalid_context),
         :ok <- validate_context_invocation_id_keys(context),
         :ok <- validate_non_conflicting_keys(params, :invalid_params_conflicting_keys),
         :ok <- validate_non_conflicting_keys(context, :invalid_context_conflicting_keys),
         :ok <- validate_context_permissions(context),
         :ok <- validate_permissions_option(permissions_option),
         {:ok, module} <- CommandRegistry.get_command(normalized_name, registry) do
      permissions = normalize_permissions(permissions_option)
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
         :ok <- validate_context_invocation_id_keys(context),
         :ok <- validate_non_conflicting_keys(params, :invalid_params_conflicting_keys),
         :ok <- validate_non_conflicting_keys(context, :invalid_context_conflicting_keys) do
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

  defp validate_permissions_option(nil), do: :ok

  defp validate_permissions_option(value) when is_map(value) do
    case validate_non_conflicting_keys(value, :invalid_permissions_conflicting_keys) do
      :ok ->
        case validate_permissions_option_keys(value) do
          :ok -> validate_permissions_option_values(value)
          {:error, _reason} = error -> error
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_permissions_option(_), do: {:error, :invalid_permissions}

  defp validate_context_permissions(context) when is_map(context) do
    case context_permissions_option(context) do
      :missing ->
        :ok

      {:present, value} when is_map(value) ->
        value
        |> validate_permissions_option()
        |> map_context_permissions_error()

      {:present, _value} ->
        {:error, :invalid_context_permissions}
    end
  end

  defp context_permissions_option(context) when is_map(context) do
    cond do
      Map.has_key?(context, :permissions) -> {:present, Map.get(context, :permissions)}
      Map.has_key?(context, "permissions") -> {:present, Map.get(context, "permissions")}
      true -> :missing
    end
  end

  defp map_context_permissions_error(:ok), do: :ok

  defp map_context_permissions_error({:error, {:invalid_permissions_conflicting_keys, keys}}),
    do: {:error, {:invalid_context_permissions_conflicting_keys, keys}}

  defp map_context_permissions_error({:error, {:invalid_permissions_keys, keys}}),
    do: {:error, {:invalid_context_permissions_keys, keys}}

  defp map_context_permissions_error({:error, {:invalid_permissions_value, key, reason}}),
    do: {:error, {:invalid_context_permissions_value, key, reason}}

  defp map_context_permissions_error({:error, {:invalid_permissions_item, key, index}}),
    do: {:error, {:invalid_context_permissions_item, key, index}}

  defp validate_permissions_option_keys(value) when is_map(value) do
    allowed_keys = ["allow", "deny", "ask"]

    unknown_keys =
      value
      |> Map.keys()
      |> Enum.map(&normalize_payload_key/1)
      |> Enum.reject(&(&1 in allowed_keys))
      |> Enum.sort()

    if unknown_keys == [] do
      :ok
    else
      {:error, {:invalid_permissions_keys, unknown_keys}}
    end
  end

  defp validate_permissions_option_values(value) when is_map(value) do
    ["allow", "deny", "ask"]
    |> Enum.reduce_while(:ok, fn key, :ok ->
      case validate_permission_bucket(permissions_bucket_value(value, key), key) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_permission_bucket(nil, _key), do: :ok

  defp validate_permission_bucket(bucket, key) when is_list(bucket) do
    bucket
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {item, index}, :ok ->
      if is_binary(item) or is_atom(item) do
        {:cont, :ok}
      else
        {:halt, {:error, {:invalid_permissions_item, key, index}}}
      end
    end)
  end

  defp validate_permission_bucket(_bucket, key),
    do: {:error, {:invalid_permissions_value, key, :must_be_list}}

  defp validate_non_conflicting_keys(value, error_tag) when is_map(value) do
    conflicting_keys =
      value
      |> Map.keys()
      |> Enum.map(&normalize_payload_key/1)
      |> Enum.frequencies()
      |> Enum.reduce([], fn
        {key, count}, acc when count > 1 -> [key | acc]
        {_key, _count}, acc -> acc
      end)
      |> Enum.sort()

    if conflicting_keys == [] do
      validate_non_conflicting_values(Map.values(value), error_tag)
    else
      {:error, {error_tag, conflicting_keys}}
    end
  end

  defp validate_non_conflicting_keys(value, error_tag) when is_list(value),
    do: validate_non_conflicting_values(value, error_tag)

  defp validate_non_conflicting_keys(_value, _error_tag), do: :ok

  defp validate_non_conflicting_values(values, error_tag) when is_list(values) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      value
      |> validate_non_conflicting_keys(error_tag)
      |> continue_or_halt()
    end)
  end

  defp continue_or_halt(:ok), do: {:cont, :ok}
  defp continue_or_halt({:error, _reason} = error), do: {:halt, error}

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

  defp normalize_payload_key(key) when is_binary(key), do: key
  defp normalize_payload_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_payload_key(key), do: inspect(key)

  defp normalize_permissions(value) when is_map(value) do
    %{
      allow: normalize_permission_list(permissions_bucket_value(value, "allow")),
      deny: normalize_permission_list(permissions_bucket_value(value, "deny")),
      ask: normalize_permission_list(permissions_bucket_value(value, "ask"))
    }
  end

  defp normalize_permissions(_), do: nil

  defp permissions_bucket_value(value, key) when is_map(value) and is_binary(key) do
    case Map.fetch(value, key) do
      {:ok, bucket_value} ->
        bucket_value

      :error ->
        Map.get(value, String.to_atom(key))
    end
  end

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
