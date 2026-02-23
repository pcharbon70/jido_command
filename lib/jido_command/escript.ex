defmodule Jido.Code.Command.Escript do
  @moduledoc false

  alias Jido.Code.Command.CLI

  @tzdata_release_ets_prefix "tzdata/priv/release_ets/"
  @fallback_tzdata_dir_name "jido_command_tzdata"

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
    data_dir = prepare_tzdata_data_dir(File.cwd!())
    Application.put_env(:tzdata, :data_dir, data_dir, persistent: true)
  end

  defp prepare_tzdata_data_dir(cwd) do
    candidates = tzdata_data_dir_candidates(cwd)

    case pick_prepared_tzdata_data_dir(candidates) do
      {:ok, data_dir} ->
        data_dir

      {:error, reasons} ->
        fallback = fallback_tzdata_data_dir()
        _ = safe_mkdir_p(fallback)
        log_tzdata_fallback(reasons, fallback)
        fallback
    end
  end

  defp tzdata_data_dir_candidates(cwd) do
    [
      normalize_env_dir(System.get_env("JIDO_COMMAND_TZDATA_DIR")),
      project_tzdata_data_dir(cwd),
      fallback_tzdata_data_dir()
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp pick_prepared_tzdata_data_dir(candidates) when is_list(candidates) do
    Enum.reduce_while(candidates, {:error, []}, fn data_dir, {:error, reasons} ->
      case ensure_tzdata_data_dir(data_dir) do
        :ok ->
          {:halt, {:ok, data_dir}}

        {:error, reason} ->
          {:cont, {:error, [{data_dir, reason} | reasons]}}
      end
    end)
  end

  defp ensure_tzdata_data_dir(data_dir) when is_binary(data_dir) do
    with :ok <- safe_mkdir_p(data_dir) do
      ensure_tzdata_release_files(data_dir)
    end
  end

  defp ensure_tzdata_release_files(data_dir) do
    if valid_tzdata_data_dir?(data_dir) do
      :ok
    else
      with :ok <- seed_tzdata_release_files(data_dir, escript_script_name()),
           true <- valid_tzdata_data_dir?(data_dir) do
        :ok
      else
        false -> {:error, :missing_release_files}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp safe_mkdir_p(path) when is_binary(path) do
    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  defp log_tzdata_fallback(reasons, fallback_path) do
    reason_text =
      reasons
      |> Enum.reverse()
      |> Enum.map_join(", ", fn {data_dir, reason} -> "#{data_dir}=#{inspect(reason)}" end)

    IO.puts(
      :stderr,
      "unable to prepare configured tzdata directories (#{reason_text}); " <>
        "falling back to #{fallback_path}"
    )
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
    Path.join(System.tmp_dir!(), @fallback_tzdata_dir_name)
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

    with :ok <- ensure_release_dir(release_dir) do
      fold_release_files(archive_path, release_dir)
    end
  end

  defp ensure_release_dir(release_dir) when is_binary(release_dir) do
    case File.mkdir_p(release_dir) do
      :ok -> :ok
      {:error, reason} -> {:error, {:release_dir_unavailable, reason}}
    end
  end

  defp fold_release_files(archive_path, release_dir)
       when is_binary(archive_path) and is_binary(release_dir) do
    case :zip.foldl(
           fn name, _get_info, get_binary, acc ->
             copy_release_file(name, get_binary, release_dir, acc)
           end,
           0,
           String.to_charlist(archive_path)
         ) do
      {:ok, copied_count} when is_integer(copied_count) ->
        {:ok, copied_count}

      {:ok, {:error, reason}} ->
        {:error, reason}

      {:error, reason} ->
        {:error, {:archive_extract_failed, reason}}
    end
  end

  defp copy_release_file(_name, _get_binary, _release_dir, {:error, _reason} = error), do: error

  defp copy_release_file(name, get_binary, release_dir, copied_count)
       when is_list(name) and is_function(get_binary, 0) and is_binary(release_dir) do
    name_string = List.to_string(name)

    if release_ets_file?(name_string) do
      target_path = Path.join(release_dir, Path.basename(name_string))

      with {:ok, content} <- safe_get_archive_entry_binary(get_binary),
           :ok <- write_release_file(target_path, content) do
        copied_count + 1
      else
        {:error, reason} -> {:error, reason}
      end
    else
      copied_count
    end
  end

  defp safe_get_archive_entry_binary(get_binary) when is_function(get_binary, 0) do
    content = get_binary.()
    if is_binary(content), do: {:ok, content}, else: {:error, :invalid_archive_entry}
  rescue
    error -> {:error, {:archive_entry_failed, error}}
  catch
    kind, reason -> {:error, {:archive_entry_failed, {kind, reason}}}
  end

  defp write_release_file(path, content) when is_binary(path) and is_binary(content) do
    case File.write(path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, {:release_write_failed, reason}}
    end
  end

  defp release_ets_file?(path) when is_binary(path) do
    String.starts_with?(path, @tzdata_release_ets_prefix) and
      release_ets_filename?(Path.basename(path))
  end

  @doc false
  @spec tzdata_release_file_version() :: pos_integer()
  def tzdata_release_file_version do
    if function_exported?(Tzdata.EtsHolder, :file_version, 0) do
      Tzdata.EtsHolder.file_version()
    else
      2
    end
  end

  defp expected_release_ets_suffix do
    ".v#{tzdata_release_file_version()}.ets"
  end

  defp release_ets_filename?(filename) when is_binary(filename) do
    String.ends_with?(filename, expected_release_ets_suffix())
  end

  defp validate_copied_release_files(copied_count)
       when is_integer(copied_count) and copied_count > 0,
       do: :ok

  defp validate_copied_release_files(_copied_count), do: {:error, :missing_release_files}

  defp valid_tzdata_data_dir?(path) when is_binary(path) do
    release_ets_dir = Path.join(path, "release_ets")

    case File.ls(release_ets_dir) do
      {:ok, files} ->
        Enum.any?(files, &release_ets_filename?/1)

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
