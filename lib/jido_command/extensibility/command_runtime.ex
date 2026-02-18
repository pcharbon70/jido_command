defmodule JidoCommand.Extensibility.CommandRuntime do
  @moduledoc """
  Executes command bodies and emits predefined `pre` and `after` hook signals.
  """

  alias JidoCommand.Extensibility.CommandDefinition
  alias Jido.Signal
  alias Jido.Signal.Bus

  @type execute_result :: {:ok, map()} | {:error, term()}

  @callback execute(CommandDefinition.t(), String.t(), map(), map()) :: execute_result()

  @spec execute(CommandDefinition.t(), map(), map()) :: execute_result()
  def execute(%CommandDefinition{} = definition, params, context) when is_map(params) do
    invocation_id = Map.get(context, :invocation_id, default_invocation_id())
    started_ms = System.monotonic_time(:millisecond)

    emit_hook(definition.hooks.pre, definition, params, context, %{
      "invocation_id" => invocation_id,
      "status" => "pre"
    })

    prompt = interpolate_template(definition.body, params)
    executor = Map.get(context, :command_executor, __MODULE__.DefaultExecutor)

    case executor.execute(definition, prompt, params, context) do
      {:ok, result} ->
        duration_ms = System.monotonic_time(:millisecond) - started_ms

        emit_hook(definition.hooks.after, definition, params, context, %{
          "invocation_id" => invocation_id,
          "status" => "ok",
          "duration_ms" => duration_ms,
          "result" => result
        })

        {:ok,
         %{
           "invocation_id" => invocation_id,
           "duration_ms" => duration_ms,
           "result" => result
         }}

      {:error, reason} ->
        duration_ms = System.monotonic_time(:millisecond) - started_ms

        emit_hook(definition.hooks.after, definition, params, context, %{
          "invocation_id" => invocation_id,
          "status" => "error",
          "duration_ms" => duration_ms,
          "error" => inspect(reason)
        })

        {:error, reason}
    end
  end

  def execute(%CommandDefinition{} = definition, params, context) when is_list(params) do
    execute(definition, Map.new(params), context)
  end

  def execute(_definition, _params, _context), do: {:error, :invalid_params}

  defp emit_hook(nil, _definition, _params, _context, _metadata), do: :ok

  defp emit_hook(type, %CommandDefinition{} = definition, params, context, metadata)
       when is_binary(type) do
    payload =
      Map.merge(metadata, %{
        "command" => definition.name,
        "params" => params
      })

    signal_attrs = [source: "/commands/#{definition.name}"]

    with {:ok, signal} <- Signal.new(normalize_signal_type(type), payload, signal_attrs) do
      bus = Map.get(context, :bus, :jido_code_bus)
      _ = Bus.publish(bus, [signal])
      :ok
    else
      _ -> :ok
    end
  end

  defp emit_hook(_invalid_type, _definition, _params, _context, _metadata), do: :ok

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

  defp default_invocation_id do
    Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end

  defp normalize_signal_type(type) do
    type
    |> String.trim()
    |> String.replace("/", ".")
  end

  defmodule DefaultExecutor do
    @moduledoc """
    Default command executor used until a model/tool runtime is plugged in.
    """

    @behaviour JidoCommand.Extensibility.CommandRuntime

    @impl true
    def execute(definition, prompt, params, _context) do
      {:ok,
       %{
         "command" => definition.name,
         "prompt" => prompt,
         "params" => params,
         "allowed_tools" => definition.allowed_tools,
         "model" => definition.model
       }}
    end
  end
end
