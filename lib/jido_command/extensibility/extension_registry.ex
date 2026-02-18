defmodule JidoCommand.Extensibility.ExtensionRegistry do
  @moduledoc """
  Central registry for loaded extensions and command modules.
  """

  use GenServer

  alias JidoCommand.Config.Loader
  alias JidoCommand.Extensibility.ExtensionLoader
  alias Jido.Signal
  alias Jido.Signal.Bus

  require Logger

  @type state :: %{
          bus: atom(),
          global_root: String.t(),
          local_root: String.t(),
          commands: map(),
          extensions: map()
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

  @spec register_extension(String.t(), GenServer.server()) :: :ok | {:error, term()}
  def register_extension(manifest_path, server \\ __MODULE__) do
    GenServer.call(server, {:register_extension, manifest_path})
  end

  @impl true
  def init(opts) do
    global_root = Keyword.get(opts, :global_root, Loader.default_global_root())
    local_root = Keyword.get(opts, :local_root, Loader.default_local_root())
    bus = Keyword.get(opts, :bus, :jido_code_bus)

    initial = %{
      bus: bus,
      global_root: global_root,
      local_root: local_root,
      commands: %{},
      extensions: %{}
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
    case load_all(%{state | commands: %{}, extensions: %{}}) do
      {:ok, reloaded} -> {:reply, :ok, reloaded}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:register_extension, manifest_path}, _from, state) do
    case ExtensionLoader.load_manifest_and_commands(manifest_path) do
      {:ok, {manifest, commands}} ->
        new_state =
          state
          |> merge_commands(commands)
          |> put_in([:extensions, manifest.name], manifest)
          |> emit_extension_loaded(manifest)

        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp load_all(state) do
    with {:ok, with_global_commands} <- load_commands_dir(state, state.global_root, :global),
         {:ok, with_global_extensions} <-
           load_extensions(with_global_commands, state.global_root, :global),
         {:ok, with_local_commands} <-
           load_commands_dir(with_global_extensions, state.local_root, :local),
         {:ok, with_local_extensions} <-
           load_extensions(with_local_commands, state.local_root, :local) do
      {:ok, with_local_extensions}
    end
  end

  defp load_commands_dir(state, root, scope) do
    commands_dir = Path.join(root, "commands")

    case ExtensionLoader.load_commands_from_directory(commands_dir,
           scope: scope,
           source: commands_dir
         ) do
      {:ok, commands} -> {:ok, merge_commands(state, commands)}
      {:error, reason} -> {:error, {:load_commands_failed, scope, commands_dir, reason}}
    end
  end

  defp load_extensions(state, root, scope) do
    extensions_root = Path.join(root, "extensions")

    ExtensionLoader.discover_manifest_paths(extensions_root)
    |> Enum.reduce_while({:ok, state}, fn manifest_path, {:ok, acc_state} ->
      case ExtensionLoader.load_manifest_and_commands(manifest_path) do
        {:ok, {manifest, commands}} ->
          updated =
            acc_state
            |> merge_commands(commands)
            |> put_in([:extensions, manifest.name], %{
              manifest
              | extension_root: manifest.extension_root
            })
            |> emit_extension_loaded(manifest)

          {:cont, {:ok, updated}}

        {:error, reason} ->
          Logger.error("Failed to load extension #{manifest_path}: #{inspect(reason)}")
          {:halt, {:error, {:load_extension_failed, scope, manifest_path, reason}}}
      end
    end)
  end

  defp merge_commands(state, commands) do
    %{state | commands: Map.merge(state.commands, commands)}
  end

  defp emit_extension_loaded(state, manifest) do
    payload = %{
      "extension_name" => manifest.name,
      "version" => manifest.version
    }

    with {:ok, signal} <-
           Signal.new("extension.loaded", payload, source: "/extensions/#{manifest.name}") do
      _ = Bus.publish(state.bus, [signal])
      state
    else
      _ -> state
    end
  end
end
