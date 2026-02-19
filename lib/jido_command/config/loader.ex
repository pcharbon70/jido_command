defmodule JidoCommand.Config.Loader do
  @moduledoc """
  Loads global and local `settings.json` files and merges them with local precedence.
  """

  alias JidoCommand.Config.Settings

  @type load_error ::
          {:invalid_json, String.t(), term()}
          | {:read_error, String.t(), term()}
          | {:invalid_settings, term()}

  @spec load(keyword()) :: {:ok, Settings.t()} | {:error, load_error()}
  def load(opts \\ []) do
    global_root = Keyword.get(opts, :global_root, default_global_root())
    local_root = Keyword.get(opts, :local_root, default_local_root())

    with {:ok, global} <- load_settings_file(Path.join(global_root, "settings.json")),
         {:ok, local} <- load_settings_file(Path.join(local_root, "settings.json")) do
      merged = deep_merge(global, local)

      case Settings.validate(merged) do
        :ok -> {:ok, Settings.from_map(merged)}
        {:error, reason} -> {:error, {:invalid_settings, reason}}
      end
    end
  end

  @spec load!(keyword()) :: Settings.t()
  def load!(opts \\ []) do
    case load(opts) do
      {:ok, settings} -> settings
      {:error, reason} -> raise "failed to load settings: #{inspect(reason)}"
    end
  end

  @spec default_global_root() :: String.t()
  def default_global_root do
    Path.join(System.user_home!(), ".jido_code")
  end

  @spec default_local_root() :: String.t()
  def default_local_root do
    Path.join(File.cwd!(), ".jido_code")
  end

  @spec load_settings_file(String.t()) :: {:ok, map()} | {:error, load_error()}
  def load_settings_file(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, map} when is_map(map) -> {:ok, map}
          {:ok, _} -> {:error, {:invalid_json, path, :root_must_be_object}}
          {:error, reason} -> {:error, {:invalid_json, path, reason}}
        end

      {:error, :enoent} ->
        {:ok, %{}}

      {:error, reason} ->
        {:error, {:read_error, path, reason}}
    end
  end

  @spec deep_merge(map(), map()) :: map()
  def deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      deep_merge(left_value, right_value)
    end)
  end

  def deep_merge(_left, right), do: right
end
