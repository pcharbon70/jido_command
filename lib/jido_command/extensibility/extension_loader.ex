defmodule JidoCommand.Extensibility.ExtensionLoader do
  @moduledoc """
  Loads commands from command directories and extension manifests.
  """

  alias JidoCommand.Extensibility.Command
  alias JidoCommand.Extensibility.ExtensionManifest

  @type command_index :: %{optional(String.t()) => map()}

  @spec load_commands_from_directory(String.t(), keyword()) ::
          {:ok, command_index()} | {:error, term()}
  def load_commands_from_directory(directory, meta \\ []) do
    if File.dir?(directory) do
      files = Path.wildcard(Path.join(directory, "*.md"))
      load_command_files(files, meta)
    else
      {:ok, %{}}
    end
  end

  @spec discover_manifest_paths(String.t()) :: [String.t()]
  def discover_manifest_paths(extensions_root) do
    if File.dir?(extensions_root) do
      Path.wildcard(Path.join([extensions_root, "*", ".jido-extension", "extension.json"]),
        match_dot: true
      )
    else
      []
    end
  end

  @spec load_from_manifest(ExtensionManifest.t()) :: {:ok, command_index()} | {:error, term()}
  def load_from_manifest(%ExtensionManifest{} = manifest) do
    command_dir = Path.expand(manifest.commands, manifest.extension_root)

    load_commands_from_directory(command_dir,
      extension: manifest.name,
      extension_version: manifest.version,
      source: manifest.manifest_path
    )
  end

  @spec load_manifest(String.t()) :: {:ok, ExtensionManifest.t()} | {:error, term()}
  def load_manifest(manifest_path) do
    ExtensionManifest.from_file(manifest_path)
  end

  @spec load_manifest_and_commands(String.t()) ::
          {:ok, {ExtensionManifest.t(), command_index()}} | {:error, term()}
  def load_manifest_and_commands(manifest_path) do
    with {:ok, manifest} <- load_manifest(manifest_path),
         {:ok, commands} <- load_from_manifest(manifest) do
      {:ok, {manifest, commands}}
    end
  end

  defp load_command_files(files, meta) do
    Enum.reduce_while(files, {:ok, %{}}, fn file, {:ok, acc} ->
      case Command.from_markdown(file) do
        {:ok, compiled} ->
          entry = %{
            module: compiled.module,
            definition: compiled.definition,
            path: file,
            meta: Map.new(meta)
          }

          {:cont, {:ok, Map.put(acc, compiled.name, entry)}}

        {:error, reason} ->
          {:halt, {:error, {:command_load_failed, file, reason}}}
      end
    end)
  end
end
