defmodule JidoCommand.Extensibility.CommandDispatcher do
  @moduledoc """
  Subscribes to `command.invoke` signals and executes registered commands.
  """

  use GenServer

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoCommand.Extensibility.ExtensionRegistry

  require Logger

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    state = %{
      bus: Keyword.get(opts, :bus, :jido_code_bus),
      registry: Keyword.get(opts, :registry, ExtensionRegistry)
    }

    case Bus.subscribe(state.bus, "command.invoke", dispatch: {:pid, target: self()}) do
      {:ok, _subscription_id} -> {:ok, state}
      {:error, reason} -> {:stop, {:subscribe_failed, reason}}
    end
  end

  @impl true
  def handle_info({:signal, %Signal{type: "command.invoke"} = signal}, state) do
    process_invoke(signal, state)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp process_invoke(%Signal{data: data} = signal, state) when is_map(data) do
    command_name = data_get(data, "name")
    params = ensure_map(data_get(data, "params", %{}))
    context = ensure_map(data_get(data, "context", %{}))
    invocation_id = data_get(data, "invocation_id", signal.id)

    with name when is_binary(name) <- command_name,
         {:ok, command_module} <- ExtensionRegistry.get_command(name, state.registry) do
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
    else
      nil ->
        Logger.warning("command.invoke signal missing command name")

      {:error, :not_found} ->
        emit_result(state.bus, "command.failed", %{
          "name" => command_name,
          "invocation_id" => invocation_id,
          "error" => "command not found"
        })
    end
  end

  defp process_invoke(_signal, _state), do: :ok

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

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_), do: %{}

  defp safe_existing_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
