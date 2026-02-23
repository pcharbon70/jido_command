defmodule Jido.Code.Command.Escript do
  @moduledoc false

  alias Jido.Code.Command.CLI

  @spec main([String.t()]) :: :ok | no_return()
  def main(args) do
    configure_tzdata_data_dir()

    case Application.ensure_all_started(:jido_command) do
      {:ok, _started} ->
        CLI.main(args)

      {:error, reason} ->
        IO.puts(:stderr, "failed to start jido_command application: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp configure_tzdata_data_dir do
    data_dir = resolve_tzdata_data_dir(File.cwd!())

    File.mkdir_p!(data_dir)
    Application.put_env(:tzdata, :data_dir, data_dir, persistent: true)
  end

  defp resolve_tzdata_data_dir(cwd) do
    normalize_env_dir(System.get_env("JIDO_COMMAND_TZDATA_DIR")) ||
      project_tzdata_data_dir(cwd) ||
      fallback_tzdata_data_dir()
  end

  defp normalize_env_dir(nil), do: nil

  defp normalize_env_dir(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: Path.expand(trimmed)
  end

  defp project_tzdata_data_dir(cwd) do
    with {:ok, root} <- find_project_root(cwd),
         local_tzdata_dir <- Path.join([root, "deps", "tzdata", "priv"]),
         true <- valid_tzdata_data_dir?(local_tzdata_dir) do
      local_tzdata_dir
    else
      _ -> nil
    end
  end

  defp fallback_tzdata_data_dir do
    Path.join(System.tmp_dir!(), "jido_command_tzdata")
  end

  defp valid_tzdata_data_dir?(path) when is_binary(path) do
    release_ets_dir = Path.join(path, "release_ets")

    case File.ls(release_ets_dir) do
      {:ok, files} ->
        Enum.any?(files, &String.ends_with?(&1, ".ets"))

      {:error, _reason} ->
        false
    end
  end

  defp find_project_root(path) when is_binary(path) do
    current = Path.expand(path)
    mix_file = Path.join(current, "mix.exs")

    if File.exists?(mix_file) do
      {:ok, current}
    else
      parent = Path.dirname(current)

      if parent == current do
        {:error, :no_mix_project}
      else
        find_project_root(parent)
      end
    end
  end
end
