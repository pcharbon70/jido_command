defmodule JidoCommand.Extensibility.CommandDispatcher do
  @moduledoc """
  Subscribes to `command.invoke` signals and executes registered commands.
  """

  use GenServer

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoCommand.Extensibility.CommandRegistry

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    max_concurrent = parse_max_concurrent(Keyword.get(opts, :max_concurrent, 5))

    state = %{
      bus: Keyword.get(opts, :bus, :jido_code_bus),
      registry: Keyword.get(opts, :registry, CommandRegistry),
      max_concurrent: max_concurrent,
      in_flight: 0,
      queue: :queue.new()
    }

    case Bus.subscribe(state.bus, "command.invoke", dispatch: {:pid, target: self()}) do
      {:ok, _subscription_id} -> {:ok, state}
      {:error, reason} -> {:stop, {:subscribe_failed, reason}}
    end
  end

  @impl true
  def handle_info({:signal, %Signal{type: "command.invoke"} = signal}, state) do
    {:noreply, process_invoke(signal, state)}
  end

  def handle_info(:invoke_finished, state) do
    reduced = %{state | in_flight: max(state.in_flight - 1, 0)}
    {:noreply, drain_queue(reduced)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp process_invoke(%Signal{data: data} = signal, state) when is_map(data) do
    case validate_invoke_payload(data, signal.id) do
      {:ok, invoke} ->
        enqueue_or_start(invoke, state)

      {:error, reason, name, invocation_id} ->
        emit_result(state.bus, "command.failed", %{
          "name" => name,
          "invocation_id" => invocation_id,
          "error" => invalid_payload_message(reason)
        })

        state
    end
  end

  defp process_invoke(%Signal{id: signal_id}, state) do
    emit_result(state.bus, "command.failed", %{
      "name" => "<invalid>",
      "invocation_id" => signal_id,
      "error" => invalid_payload_message(:payload_must_be_map)
    })

    state
  end

  defp execute_invoke(
         %{name: name, params: params, context: context, invocation_id: invocation_id},
         state
       ) do
    case CommandRegistry.get_command(name, state.registry) do
      {:ok, command_module} ->
        exec_context =
          context
          |> Map.put(:bus, state.bus)
          |> Map.put(:invocation_id, invocation_id)

        case Jido.Exec.run(command_module, params, exec_context) do
          {:ok, result} ->
            emit_result(state.bus, "command.completed", %{
              "name" => name,
              "invocation_id" => invocation_id,
              "result" => result
            })

          {:error, reason} ->
            emit_result(state.bus, "command.failed", %{
              "name" => name,
              "invocation_id" => invocation_id,
              "error" => inspect(reason)
            })
        end

      {:error, :not_found} ->
        emit_result(state.bus, "command.failed", %{
          "name" => name,
          "invocation_id" => invocation_id,
          "error" => "command not found"
        })
    end
  end

  defp enqueue_or_start(invoke, state) do
    if state.in_flight < state.max_concurrent do
      start_invoke(state, invoke)
    else
      %{state | queue: :queue.in(invoke, state.queue)}
    end
  end

  defp start_invoke(state, invoke) do
    parent = self()

    spawn(fn ->
      try do
        execute_invoke(invoke, state)
      rescue
        error ->
          emit_result(state.bus, "command.failed", %{
            "name" => invoke.name,
            "invocation_id" => invoke.invocation_id,
            "error" => inspect(error)
          })
      catch
        kind, reason ->
          emit_result(state.bus, "command.failed", %{
            "name" => invoke.name,
            "invocation_id" => invoke.invocation_id,
            "error" => inspect({kind, reason})
          })
      after
        send(parent, :invoke_finished)
      end
    end)

    %{state | in_flight: state.in_flight + 1}
  end

  defp drain_queue(state) do
    if state.in_flight >= state.max_concurrent do
      state
    else
      case :queue.out(state.queue) do
        {{:value, invoke}, rest} ->
          state
          |> Map.put(:queue, rest)
          |> start_invoke(invoke)
          |> drain_queue()

        {:empty, _queue} ->
          state
      end
    end
  end

  defp parse_max_concurrent(value) when is_integer(value) and value > 0, do: value
  defp parse_max_concurrent(_), do: 5

  defp validate_invoke_payload(data, fallback_invocation_id) do
    raw_name = data_get(data, "name")
    normalized_name = normalize_name(raw_name)

    normalized_invocation_id =
      normalize_invocation_id(data_get(data, "invocation_id"), fallback_invocation_id)

    with {:ok, name} <- validate_name(raw_name),
         {:ok, params} <- validate_params(data_get(data, "params", :missing)),
         {:ok, context} <- validate_context(data_get(data, "context", :missing)),
         {:ok, invocation_id} <-
           validate_invocation_id(
             data_get(data, "invocation_id", :missing),
             fallback_invocation_id
           ) do
      {:ok, %{name: name, params: params, context: context, invocation_id: invocation_id}}
    else
      {:error, reason} ->
        {:error, reason, normalized_name, normalized_invocation_id}
    end
  end

  defp validate_name(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:error, :invalid_name}
    else
      {:ok, trimmed}
    end
  end

  defp validate_name(nil), do: {:error, :missing_name}
  defp validate_name(_), do: {:error, :invalid_name}

  defp validate_params(:missing), do: {:error, :missing_params}
  defp validate_params(params) when is_map(params), do: {:ok, params}
  defp validate_params(_), do: {:error, :invalid_params}

  defp validate_context(:missing), do: {:ok, %{}}
  defp validate_context(context) when is_map(context), do: {:ok, context}
  defp validate_context(_), do: {:error, :invalid_context}

  defp validate_invocation_id(:missing, fallback), do: {:ok, fallback}

  defp validate_invocation_id(value, _fallback) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:error, :invalid_invocation_id}
    else
      {:ok, trimmed}
    end
  end

  defp validate_invocation_id(_value, _fallback), do: {:error, :invalid_invocation_id}

  defp normalize_name(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: "<invalid>", else: trimmed
  end

  defp normalize_name(_), do: "<invalid>"

  defp normalize_invocation_id(value, fallback) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: fallback, else: trimmed
  end

  defp normalize_invocation_id(_value, fallback), do: fallback

  defp invalid_payload_message(:payload_must_be_map),
    do: "invalid command.invoke payload: data must be an object"

  defp invalid_payload_message(:missing_name),
    do: "invalid command.invoke payload: name is required"

  defp invalid_payload_message(:invalid_name),
    do: "invalid command.invoke payload: name must be a non-empty string"

  defp invalid_payload_message(:missing_params),
    do: "invalid command.invoke payload: params is required"

  defp invalid_payload_message(:invalid_params),
    do: "invalid command.invoke payload: params must be an object"

  defp invalid_payload_message(:invalid_context),
    do: "invalid command.invoke payload: context must be an object when provided"

  defp invalid_payload_message(:invalid_invocation_id),
    do: "invalid command.invoke payload: invocation_id must be a non-empty string when provided"

  defp emit_result(bus, type, payload) do
    case Signal.new(type, payload, source: "/dispatcher") do
      {:ok, signal} ->
        _ = Bus.publish(bus, [signal])
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp data_get(map, key, default \\ nil) when is_map(map) do
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
end
