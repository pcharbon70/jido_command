defmodule JidoCommand.Extensibility.CommandRegistry do
  @moduledoc """
  Central registry for loaded command modules.
  """

  use GenServer

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoCommand.Config.Loader
  alias JidoCommand.Extensibility.Command
  alias JidoCommand.Extensibility.CommandLoader

  @type state :: %{
          bus: atom(),
          global_root: String.t(),
          local_root: String.t(),
          default_model: String.t() | nil,
          commands: map()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec get_command(String.t(), GenServer.server()) :: {:ok, module()} | {:error, :not_found}
  def get_command(name, server \\ __MODULE__) do
    GenServer.call(server, {:get_command, name})
  end

  @spec get_command_entry(String.t(), GenServer.server()) :: {:ok, map()} | {:error, :not_found}
  def get_command_entry(name, server \\ __MODULE__) do
    GenServer.call(server, {:get_command_entry, name})
  end

  @spec list_commands(GenServer.server()) :: [String.t()]
  def list_commands(server \\ __MODULE__) do
    GenServer.call(server, :list_commands)
  end

  @spec reload(GenServer.server()) :: :ok | {:error, term()}
  def reload(server \\ __MODULE__) do
    GenServer.call(server, :reload)
  end

  @spec register_command(String.t(), GenServer.server()) :: :ok | {:error, term()}
  def register_command(command_path, server \\ __MODULE__) when is_binary(command_path) do
    GenServer.call(server, {:register_command, command_path})
  end

  @spec unregister_command(String.t(), GenServer.server()) ::
          :ok | {:error, :not_found | :invalid_name}
  def unregister_command(command_name, server \\ __MODULE__) when is_binary(command_name) do
    GenServer.call(server, {:unregister_command, command_name})
  end

  @impl true
  def init(opts) do
    global_root = Keyword.get(opts, :global_root, Loader.default_global_root())
    local_root = Keyword.get(opts, :local_root, Loader.default_local_root())
    bus = Keyword.get(opts, :bus, :jido_code_bus)
    default_model = parse_default_model(Keyword.get(opts, :default_model))

    initial = %{
      bus: bus,
      global_root: global_root,
      local_root: local_root,
      default_model: default_model,
      commands: %{}
    }

    case load_all(initial) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:get_command, name}, _from, state) do
    case Map.get(state.commands, name) do
      %{module: module} -> {:reply, {:ok, module}, state}
      nil -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:get_command_entry, name}, _from, state) do
    case Map.get(state.commands, name) do
      nil -> {:reply, {:error, :not_found}, state}
      entry -> {:reply, {:ok, entry}, state}
    end
  end

  def handle_call(:list_commands, _from, state) do
    names = state.commands |> Map.keys() |> Enum.sort()
    {:reply, names, state}
  end

  def handle_call(:reload, _from, state) do
    previous_count = map_size(state.commands)

    case load_all(%{state | commands: %{}}) do
      {:ok, reloaded} ->
        emit_lifecycle_signal(reloaded, "command.registry.reloaded", %{
          "previous_count" => previous_count,
          "current_count" => map_size(reloaded.commands)
        })

        {:reply, :ok, reloaded}

      {:error, reason} ->
        emit_failure_signal(state, "reload", reason, %{
          "previous_count" => previous_count,
          "current_count" => map_size(state.commands)
        })

        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:register_command, command_path}, _from, state) do
    case load_command_file(command_path, state.default_model) do
      {:ok, {name, entry}} ->
        updated = %{state | commands: Map.put(state.commands, name, entry)}

        emit_lifecycle_signal(updated, "command.registered", %{
          "name" => name,
          "path" => entry.path,
          "scope" => to_string(entry.meta[:scope]),
          "current_count" => map_size(updated.commands)
        })

        {:reply, :ok, updated}

      {:error, reason} ->
        emit_failure_signal(state, "register", reason, %{"path" => Path.expand(command_path)})
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:unregister_command, command_name}, _from, state) do
    normalized_name = String.trim(command_name)

    cond do
      normalized_name == "" ->
        emit_failure_signal(state, "unregister", :invalid_name, %{"name" => command_name})
        {:reply, {:error, :invalid_name}, state}

      Map.has_key?(state.commands, normalized_name) ->
        updated = %{state | commands: Map.delete(state.commands, normalized_name)}

        emit_lifecycle_signal(updated, "command.unregistered", %{
          "name" => normalized_name,
          "current_count" => map_size(updated.commands)
        })

        {:reply, :ok, updated}

      true ->
        emit_failure_signal(state, "unregister", :not_found, %{"name" => normalized_name})
        {:reply, {:error, :not_found}, state}
    end
  end

  defp load_all(state) do
    with {:ok, with_global_commands} <- load_commands_dir(state, state.global_root, :global) do
      load_commands_dir(with_global_commands, state.local_root, :local)
    end
  end

  defp load_commands_dir(state, root, scope) do
    commands_dir = Path.join(root, "commands")

    case CommandLoader.load_from_directory(commands_dir,
           scope: scope,
           source: commands_dir,
           default_model: state.default_model
         ) do
      {:ok, commands} -> {:ok, merge_commands(state, commands)}
      {:error, reason} -> {:error, {:load_commands_failed, scope, commands_dir, reason}}
    end
  end

  defp merge_commands(state, commands) do
    %{state | commands: Map.merge(state.commands, commands)}
  end

  defp load_command_file(command_path, default_model) do
    expanded_path = Path.expand(command_path)

    if File.regular?(expanded_path) do
      case Command.from_markdown(expanded_path, default_model: default_model) do
        {:ok, compiled} ->
          entry = %{
            module: compiled.module,
            definition: compiled.definition,
            path: expanded_path,
            meta: %{scope: :manual, source: Path.dirname(expanded_path)}
          }

          {:ok, {compiled.name, entry}}

        {:error, reason} ->
          {:error, {:command_load_failed, expanded_path, reason}}
      end
    else
      {:error, {:command_file_not_found, expanded_path}}
    end
  end

  defp parse_default_model(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp parse_default_model(_), do: nil

  defp emit_lifecycle_signal(state, type, data) do
    attrs = [source: "/jido_command/registry"]

    with {:ok, signal} <- Signal.new(type, data, attrs),
         {:ok, _recorded} <- Bus.publish(state.bus, [signal]) do
      :ok
    else
      _ -> :ok
    end
  end

  defp emit_failure_signal(state, operation, reason, extra_data) do
    data =
      Map.merge(
        %{
          "operation" => operation,
          "error" => format_error(reason)
        },
        extra_data
      )

    emit_lifecycle_signal(state, "command.registry.failed", data)
  end

  defp format_error(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp format_error(reason), do: inspect(reason)
end
