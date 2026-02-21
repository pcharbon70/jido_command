defmodule JidoCommand.Extensibility.CommandRuntime do
  @moduledoc """
  Executes command bodies and emits predefined `pre` and `after` hook signals.
  """

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoCommand.Extensibility.CommandDefinition

  @type execute_result :: {:ok, map()} | {:error, term()}
  @pre_hook_signal "jido.hooks.pre"
  @after_hook_signal "jido.hooks.after"

  @callback execute(CommandDefinition.t(), String.t(), map(), map()) :: execute_result()

  @spec execute(CommandDefinition.t(), map(), map()) :: execute_result()
  def execute(%CommandDefinition{} = definition, params, context) when is_map(params) do
    execution_context = apply_tool_constraints(context, definition.allowed_tools)

    invocation_id =
      execution_context
      |> context_invocation_id()
      |> normalize_invocation_id(default_invocation_id())

    started_ms = System.monotonic_time(:millisecond)

    emit_hook(definition.hooks.pre, @pre_hook_signal, definition, params, execution_context, %{
      "invocation_id" => invocation_id,
      "status" => "pre"
    })

    prompt = interpolate_template(definition.body, params)
    executor = Map.get(execution_context, :command_executor, __MODULE__.DefaultExecutor)

    case execute_with_error_capture(executor, definition, prompt, params, execution_context) do
      {:ok, result} ->
        duration_ms = System.monotonic_time(:millisecond) - started_ms

        emit_hook(
          definition.hooks.after,
          @after_hook_signal,
          definition,
          params,
          execution_context,
          %{
            "invocation_id" => invocation_id,
            "status" => "ok",
            "duration_ms" => duration_ms,
            "result" => result
          }
        )

        {:ok,
         %{
           "invocation_id" => invocation_id,
           "duration_ms" => duration_ms,
           "result" => result
         }}

      {:error, reason} ->
        duration_ms = System.monotonic_time(:millisecond) - started_ms

        emit_hook(
          definition.hooks.after,
          @after_hook_signal,
          definition,
          params,
          execution_context,
          %{
            "invocation_id" => invocation_id,
            "status" => "error",
            "duration_ms" => duration_ms,
            "error" => inspect(reason)
          }
        )

        {:error, reason}
    end
  end

  def execute(%CommandDefinition{} = definition, params, context) when is_list(params) do
    execute(definition, Map.new(params), context)
  end

  def execute(_definition, _params, _context), do: {:error, :invalid_params}

  defp execute_with_error_capture(executor, definition, prompt, params, context) do
    result = executor.execute(definition, prompt, params, context)

    case result do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_executor_response, other}}
    end
  rescue
    error ->
      {:error, {:executor_exception, error, __STACKTRACE__}}
  catch
    kind, reason ->
      {:error, {:executor_throw, kind, reason}}
  end

  defp emit_hook(false, _type, _definition, _params, _context, _metadata), do: :ok

  defp emit_hook(true, type, %CommandDefinition{} = definition, params, context, metadata)
       when is_binary(type) do
    payload =
      Map.merge(metadata, %{
        "command" => definition.name,
        "params" => params
      })

    signal_attrs = [source: "/commands/#{definition.name}"]

    case Signal.new(type, payload, signal_attrs) do
      {:ok, signal} ->
        bus = Map.get(context, :bus, :jido_code_bus)
        _ = Bus.publish(bus, [signal])
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp emit_hook(_invalid_type, _type, _definition, _params, _context, _metadata), do: :ok

  defp context_invocation_id(context) when is_map(context) do
    case Map.fetch(context, :invocation_id) do
      {:ok, value} -> value
      :error -> Map.get(context, "invocation_id")
    end
  end

  defp interpolate_template(template, params) when is_binary(template) and is_map(params) do
    Enum.reduce(params, template, fn {key, value}, acc ->
      placeholder = "{{#{key}}}"
      String.replace(acc, placeholder, render_value(value))
    end)
  end

  defp interpolate_template(template, _params), do: template

  defp render_value(value) when is_binary(value), do: value
  defp render_value(value) when is_atom(value), do: Atom.to_string(value)
  defp render_value(value), do: inspect(value)

  defp apply_tool_constraints(context, allowed_tools)
       when is_map(context) and is_list(allowed_tools) do
    normalized_allowed_tools = normalize_tool_list(allowed_tools)
    permissions = context_permissions(context) |> normalize_permissions()

    constrained_permissions =
      case normalized_allowed_tools do
        [] -> permissions
        _ -> filter_permissions_by_allowed_tools(permissions, normalized_allowed_tools)
      end

    context
    |> Map.delete("permissions")
    |> Map.delete("allowed_tools")
    |> Map.put(:permissions, constrained_permissions)
    |> Map.put(:allowed_tools, normalized_allowed_tools)
  end

  defp apply_tool_constraints(context, _allowed_tools) when is_map(context), do: context

  defp apply_tool_constraints(_context, _allowed_tools),
    do: %{permissions: %{allow: [], deny: [], ask: []}}

  defp context_permissions(context) when is_map(context) do
    case Map.fetch(context, :permissions) do
      {:ok, value} -> value
      :error -> Map.get(context, "permissions")
    end
  end

  defp normalize_permissions(value) when is_map(value) do
    %{
      allow: normalize_permission_list(permission_bucket_value(value, :allow, "allow")),
      deny: normalize_permission_list(permission_bucket_value(value, :deny, "deny")),
      ask: normalize_permission_list(permission_bucket_value(value, :ask, "ask"))
    }
  end

  defp normalize_permissions(_), do: %{allow: [], deny: [], ask: []}

  defp permission_bucket_value(value, atom_key, string_key)
       when is_map(value) and is_atom(atom_key) and is_binary(string_key) do
    case Map.fetch(value, atom_key) do
      {:ok, bucket_value} -> bucket_value
      :error -> Map.get(value, string_key)
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

  defp normalize_tool_list(list) when is_list(list) do
    list
    |> Enum.reduce([], fn tool, acc ->
      case normalize_permission(tool) do
        nil -> acc
        normalized -> [normalized | acc]
      end
    end)
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp normalize_tool_list(_), do: []

  defp filter_permissions_by_allowed_tools(permissions, allowed_tools)
       when is_map(permissions) and is_list(allowed_tools) do
    %{
      allow: filter_permission_bucket(Map.get(permissions, :allow, []), allowed_tools),
      deny: filter_permission_bucket(Map.get(permissions, :deny, []), allowed_tools),
      ask: filter_permission_bucket(Map.get(permissions, :ask, []), allowed_tools)
    }
  end

  defp filter_permission_bucket(permissions, allowed_tools)
       when is_list(permissions) and is_list(allowed_tools) do
    from_allowed =
      Enum.filter(allowed_tools, fn tool ->
        Enum.any?(permissions, &permission_matches_tool?(&1, tool))
      end)

    from_exact_permissions =
      Enum.filter(permissions, fn permission ->
        exact_tool?(permission) and
          Enum.any?(allowed_tools, &allowed_matches_exact_permission?(&1, permission))
      end)

    Enum.uniq(from_allowed ++ from_exact_permissions)
  end

  defp filter_permission_bucket(_permissions, _allowed_tools), do: []

  defp permission_matches_tool?(permission, tool)
       when is_binary(permission) and is_binary(tool) do
    permission == tool or wildcard_permission_match?(permission, tool)
  end

  defp permission_matches_tool?(_permission, _tool), do: false

  defp exact_tool?(permission) when is_binary(permission),
    do: not String.contains?(permission, "*")

  defp exact_tool?(_permission), do: false

  defp allowed_matches_exact_permission?(allowed_tool, permission)
       when is_binary(allowed_tool) and is_binary(permission) do
    allowed_tool == permission or wildcard_permission_match?(allowed_tool, permission)
  end

  defp allowed_matches_exact_permission?(_allowed_tool, _permission), do: false

  defp wildcard_permission_match?(permission, tool)
       when is_binary(permission) and is_binary(tool) do
    if String.contains?(permission, "*") do
      pattern =
        permission
        |> Regex.escape()
        |> String.replace("\\*", ".*")

      Regex.match?(~r/\A#{pattern}\z/, tool)
    else
      false
    end
  end

  defp normalize_invocation_id(value, fallback) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: fallback, else: trimmed
  end

  defp normalize_invocation_id(_value, fallback), do: fallback

  defp default_invocation_id do
    Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end

  defmodule DefaultExecutor do
    @moduledoc """
    Default command executor used until a model/tool runtime is plugged in.
    """

    @behaviour JidoCommand.Extensibility.CommandRuntime

    @impl true
    def execute(definition, prompt, params, context) do
      permissions =
        case Map.get(context, :permissions) do
          map when is_map(map) -> map
          _ -> %{}
        end

      {:ok,
       %{
         "command" => definition.name,
         "prompt" => prompt,
         "params" => params,
         "allowed_tools" => definition.allowed_tools,
         "model" => definition.model,
         "permissions" => permissions
       }}
    end
  end
end
