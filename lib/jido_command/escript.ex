defmodule Jido.Code.Command.Escript do
  @moduledoc false

  alias Jido.Code.Command.CLI

  @tzdata_release_ets_prefix "tzdata/priv/release_ets/"

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
    maybe_seed_tzdata_release_files(data_dir)
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

  defp maybe_seed_tzdata_release_files(data_dir) do
    if valid_tzdata_data_dir?(data_dir) do
      :ok
    else
      _ = seed_tzdata_release_files(data_dir, escript_script_name())
      :ok
    end
  end

  @doc false
  @spec seed_tzdata_release_files(String.t(), String.t() | nil) :: :ok | {:error, term()}
  def seed_tzdata_release_files(_data_dir, nil), do: {:error, :script_name_unavailable}

  def seed_tzdata_release_files(data_dir, script_path)
      when is_binary(data_dir) and is_binary(script_path) do
    with {:ok, archive_bin} <- extract_escript_archive(script_path),
         {:ok, archive_path} <- write_archive_to_temp_file(archive_bin) do
      try do
        with {:ok, copied_count} <- copy_release_files_from_archive(archive_path, data_dir) do
          validate_copied_release_files(copied_count)
        end
      after
        File.rm(archive_path)
      end
    end
  end

  defp escript_script_name do
    case :escript.script_name() do
      script_name when is_list(script_name) and script_name != [] ->
        List.to_string(script_name)

      _other ->
        nil
    end
  rescue
    _ -> nil
  end

  defp extract_escript_archive(script_path) when is_binary(script_path) do
    charlist_path = String.to_charlist(script_path)

    with {:ok, sections} <- :escript.extract(charlist_path, []),
         archive when is_binary(archive) <- Keyword.get(sections, :archive) do
      {:ok, archive}
    else
      {:error, reason} -> {:error, {:escript_extract_failed, reason}}
      nil -> {:error, :missing_archive_section}
    end
  end

  defp write_archive_to_temp_file(archive_bin) when is_binary(archive_bin) do
    archive_name =
      "jido_command_escript_archive_#{System.unique_integer([:positive, :monotonic])}.zip"

    archive_path = Path.join(System.tmp_dir!(), archive_name)

    case File.write(archive_path, archive_bin) do
      :ok -> {:ok, archive_path}
      {:error, reason} -> {:error, {:archive_write_failed, reason}}
    end
  end

  defp copy_release_files_from_archive(archive_path, data_dir)
       when is_binary(archive_path) and is_binary(data_dir) do
    release_dir = Path.join(data_dir, "release_ets")
    File.mkdir_p!(release_dir)

    case :zip.foldl(
           fn name, _get_info, get_binary, copied_count ->
             copy_release_file(name, get_binary, release_dir, copied_count)
           end,
           0,
           String.to_charlist(archive_path)
         ) do
      {:ok, copied_count} ->
        {:ok, copied_count}

      {:error, reason} ->
        {:error, {:archive_extract_failed, reason}}
    end
  end

  defp copy_release_file(name, get_binary, release_dir, copied_count)
       when is_list(name) and is_function(get_binary, 0) and is_binary(release_dir) do
    name_string = List.to_string(name)

    if release_ets_file?(name_string) do
      target_path = Path.join(release_dir, Path.basename(name_string))
      File.write!(target_path, get_binary.())
      copied_count + 1
    else
      copied_count
    end
  end

  defp release_ets_file?(path) when is_binary(path) do
    String.starts_with?(path, @tzdata_release_ets_prefix) and
      String.ends_with?(path, ".ets")
  end

  defp validate_copied_release_files(copied_count)
       when is_integer(copied_count) and copied_count > 0,
       do: :ok

  defp validate_copied_release_files(_copied_count), do: {:error, :missing_release_files}

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
