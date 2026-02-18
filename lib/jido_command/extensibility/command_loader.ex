defmodule JidoCommand.Extensibility.CommandLoader do
  @moduledoc """
  Loads markdown command files from command directories.
  """

  alias JidoCommand.Extensibility.Command

  @type command_index :: %{optional(String.t()) => map()}

  @spec load_from_directory(String.t(), keyword()) :: {:ok, command_index()} | {:error, term()}
  def load_from_directory(directory, meta \\ []) do
    if File.dir?(directory) do
      files = Path.wildcard(Path.join(directory, "*.md"))
      load_command_files(files, meta)
    else
      {:ok, %{}}
    end
  end

  defp load_command_files(files, meta) do
    default_model = Keyword.get(meta, :default_model)
    stored_meta = meta |> Keyword.delete(:default_model) |> Map.new()

    Enum.reduce_while(files, {:ok, %{}}, fn file, {:ok, acc} ->
      case Command.from_markdown(file, default_model: default_model) do
        {:ok, compiled} ->
          entry = %{
            module: compiled.module,
            definition: compiled.definition,
            path: file,
            meta: stored_meta
          }

          {:cont, {:ok, Map.put(acc, compiled.name, entry)}}

        {:error, reason} ->
          {:halt, {:error, {:command_load_failed, file, reason}}}
      end
    end)
  end
end
