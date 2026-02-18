defmodule JidoCommand.Extensibility.ExtensionManifest do
  @moduledoc """
  Parses extension manifests (`extension.json`).
  """

  @type t :: %__MODULE__{
          name: String.t(),
          version: String.t(),
          description: String.t() | nil,
          commands: String.t(),
          signals: map(),
          manifest_path: String.t(),
          extension_root: String.t()
        }

  defstruct [:name, :version, :description, :commands, :signals, :manifest_path, :extension_root]

  @spec from_file(String.t()) :: {:ok, t()} | {:error, term()}
  def from_file(path) do
    with {:ok, content} <- File.read(path),
         {:ok, raw} <- Jason.decode(content),
         {:ok, manifest} <- validate(raw, path) do
      {:ok, manifest}
    else
      {:error, _} = error -> error
      other -> {:error, {:invalid_manifest, path, other}}
    end
  end

  defp validate(raw, path) when is_map(raw) do
    with {:ok, name} <- fetch_required_string(raw, "name"),
         {:ok, version} <- fetch_required_string(raw, "version"),
         {:ok, commands} <- fetch_required_string(raw, "commands") do
      {:ok,
       %__MODULE__{
         name: name,
         version: version,
         description: fetch_optional_string(raw, "description"),
         commands: commands,
         signals: Map.get(raw, "signals", %{}),
         manifest_path: path,
         extension_root: path |> Path.dirname() |> Path.dirname()
       }}
    end
  end

  defp validate(_raw, path), do: {:error, {:invalid_manifest, path, :root_must_be_object}}

  defp fetch_required_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_or_invalid_field, key}}
    end
  end

  defp fetch_optional_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) -> value
      _ -> nil
    end
  end
end
