defmodule JidoCommand.Extensibility.ExtensionRegistry do
  @moduledoc """
  Central registry for loaded extensions and command modules.
  """

  use GenServer

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoCommand.Config.Loader
  alias JidoCommand.Extensibility.ExtensionLoader

  require Logger

  @type state :: %{
          bus: atom(),
          global_root: String.t(),
          local_root: String.t(),
          default_model: String.t() | nil,
          extension_policy: %{enabled: MapSet.t(String.t()), disabled: MapSet.t(String.t())},
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
    default_model = parse_default_model(Keyword.get(opts, :default_model))
    extension_policy = parse_extension_policy(opts)

    initial = %{
      bus: bus,
      global_root: global_root,
      local_root: local_root,
      default_model: default_model,
      extension_policy: extension_policy,
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
    with {:ok, manifest} <- ExtensionLoader.load_manifest(manifest_path),
         :ok <- ensure_extension_allowed(state, manifest.name),
         {:ok, commands} <-
           ExtensionLoader.load_from_manifest(manifest, default_model: state.default_model) do
      new_state = merge_extension(state, manifest, commands)
      {:reply, :ok, new_state}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      {:extension_not_allowed, extension_name} ->
        {:reply, {:error, {:extension_not_allowed, extension_name}}, state}
    end
  end

  defp load_all(state) do
    with {:ok, with_global_commands} <- load_commands_dir(state, state.global_root, :global),
         {:ok, with_global_extensions} <-
           load_extensions(with_global_commands, state.global_root, :global),
         {:ok, with_local_commands} <-
           load_commands_dir(with_global_extensions, state.local_root, :local) do
      load_extensions(with_local_commands, state.local_root, :local)
    end
  end

  defp load_commands_dir(state, root, scope) do
    commands_dir = Path.join(root, "commands")

    case ExtensionLoader.load_commands_from_directory(commands_dir,
           scope: scope,
           source: commands_dir,
           default_model: state.default_model
         ) do
      {:ok, commands} -> {:ok, merge_commands(state, commands)}
      {:error, reason} -> {:error, {:load_commands_failed, scope, commands_dir, reason}}
    end
  end

  defp load_extensions(state, root, scope) do
    extensions_root = Path.join(root, "extensions")

    ExtensionLoader.discover_manifest_paths(extensions_root)
    |> Enum.reduce_while({:ok, state}, fn manifest_path, {:ok, acc_state} ->
      case load_extension(acc_state, manifest_path) do
        {:ok, updated} ->
          {:cont, {:ok, updated}}

        {:error, reason} ->
          Logger.error("Failed to load extension #{manifest_path}: #{inspect(reason)}")
          {:halt, {:error, {:load_extension_failed, scope, manifest_path, reason}}}
      end
    end)
  end

  defp load_extension(state, manifest_path) do
    with {:ok, manifest} <- ExtensionLoader.load_manifest(manifest_path),
         :ok <- ensure_extension_allowed_for_load(state, manifest, manifest_path),
         {:ok, commands} <-
           ExtensionLoader.load_from_manifest(manifest, default_model: state.default_model) do
      {:ok, merge_extension(state, manifest, commands)}
    end
  end

  defp ensure_extension_allowed_for_load(state, manifest, manifest_path) do
    if extension_allowed?(state, manifest.name) do
      :ok
    else
      Logger.debug("Skipping disabled extension #{manifest.name} from #{manifest_path}")
      {:ok, state}
    end
  end

  defp merge_commands(state, commands) do
    %{state | commands: Map.merge(state.commands, commands)}
  end

  defp merge_extension(state, manifest, commands) do
    state
    |> merge_commands(commands)
    |> put_in([:extensions, manifest.name], manifest)
    |> emit_extension_loaded(manifest)
  end

  defp parse_extension_policy(opts) do
    %{
      enabled:
        opts
        |> Keyword.get(:extensions_enabled, [])
        |> normalize_extension_names()
        |> MapSet.new(),
      disabled:
        opts
        |> Keyword.get(:extensions_disabled, [])
        |> normalize_extension_names()
        |> MapSet.new()
    }
  end

  defp normalize_extension_names(values) when is_list(values) do
    values
    |> Enum.flat_map(fn
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: [], else: [trimmed]

      _ ->
        []
    end)
    |> Enum.uniq()
  end

  defp normalize_extension_names(_), do: []

  defp parse_default_model(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp parse_default_model(_), do: nil

  defp ensure_extension_allowed(state, extension_name) do
    if extension_allowed?(state, extension_name) do
      :ok
    else
      {:extension_not_allowed, extension_name}
    end
  end

  defp extension_allowed?(state, extension_name) do
    policy = Map.get(state, :extension_policy, %{enabled: MapSet.new(), disabled: MapSet.new()})

    not MapSet.member?(policy.disabled, extension_name) and
      (MapSet.size(policy.enabled) == 0 or MapSet.member?(policy.enabled, extension_name))
  end

  defp emit_extension_loaded(state, manifest) do
    payload = %{
      "extension_name" => manifest.name,
      "version" => manifest.version
    }

    case Signal.new("extension.loaded", payload, source: "/extensions/#{manifest.name}") do
      {:ok, signal} ->
        _ = Bus.publish(state.bus, [signal])
        state

      {:error, _reason} ->
        state
    end
  end
end
