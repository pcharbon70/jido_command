defmodule JidoCommand.Extensibility.ExtensionManifest do
  @moduledoc """
  Parses extension manifests (`extension.json`).
  """

  alias Jido.Signal.Router.Validator

  @allowed_signal_keys ["emits", "subscribes"]

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
    end
  end

  defp validate(raw, path) when is_map(raw) do
    with {:ok, name} <- fetch_required_string(raw, "name"),
         {:ok, version} <- fetch_required_string(raw, "version"),
         {:ok, commands} <- fetch_required_string(raw, "commands"),
         {:ok, description} <- fetch_optional_string(raw, "description", path),
         {:ok, signals} <- validate_signals(raw, path) do
      {:ok,
       %__MODULE__{
         name: name,
         version: version,
         description: description,
         commands: commands,
         signals: signals,
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

  defp fetch_optional_string(map, key, _path) do
    case Map.get(map, key) do
      nil -> {:ok, nil}
      value when is_binary(value) -> {:ok, value}
      _ -> {:error, {:missing_or_invalid_field, key}}
    end
  end

  defp validate_signals(map, path) do
    case Map.get(map, "signals", %{}) do
      signals when is_map(signals) ->
        validate_signals_map(signals, path)

      _ ->
        {:error, {:invalid_manifest, path, {:invalid_signals, :must_be_object}}}
    end
  end

  defp validate_signals_map(signals, path) do
    with :ok <- validate_signal_keys(signals, path),
         {:ok, emits} <- validate_signal_list(signals, "emits", path),
         {:ok, subscribes} <- validate_signal_list(signals, "subscribes", path) do
      {:ok, %{"emits" => emits, "subscribes" => subscribes}}
    end
  end

  defp validate_signal_keys(signals, path) do
    unknown_keys = signals |> Map.keys() |> Enum.reject(&(&1 in @allowed_signal_keys))

    if unknown_keys == [] do
      :ok
    else
      {:error, {:invalid_manifest, path, {:invalid_signals, {:unknown_keys, unknown_keys}}}}
    end
  end

  defp validate_signal_list(signals, key, path) do
    case Map.get(signals, key, []) do
      list when is_list(list) ->
        list
        |> Enum.reduce_while([], &accumulate_signal_entry(&1, &2, key, path))
        |> finalize_signal_list()

      _ ->
        {:error, {:invalid_manifest, path, {:invalid_signals, {key, :must_be_array}}}}
    end
  end

  defp accumulate_signal_entry(entry, acc, key, path) do
    case validate_signal_entry(entry, key, path) do
      {:ok, signal_path} -> {:cont, [signal_path | acc]}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp finalize_signal_list({:error, reason}), do: {:error, reason}
  defp finalize_signal_list(list), do: {:ok, Enum.reverse(list)}

  defp validate_signal_entry(entry, key, path) when is_binary(entry) do
    signal_path = String.trim(entry)

    if signal_path == "" do
      {:error, {:invalid_manifest, path, {:invalid_signals, {key, :must_be_nonempty_string}}}}
    else
      validate_signal_path(signal_path, key, path)
    end
  end

  defp validate_signal_entry(_entry, key, path) do
    {:error, {:invalid_manifest, path, {:invalid_signals, {key, :must_be_string}}}}
  end

  defp validate_signal_path(signal_path, key, path) do
    normalized = signal_path |> String.trim() |> String.replace("/", ".")

    case Validator.validate_path(normalized) do
      {:ok, _} ->
        {:ok, signal_path}

      {:error, reason} ->
        {:error, {:invalid_manifest, path, {:invalid_signals, {key, signal_path, reason}}}}
    end
  end
end
