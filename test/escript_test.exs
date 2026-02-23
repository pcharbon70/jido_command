defmodule Jido.Code.Command.EscriptTest do
  use ExUnit.Case, async: true

  alias Jido.Code.Command.Escript

  test "seed_tzdata_release_files copies release ETS files from an escript archive" do
    tmp_dir = unique_tmp_dir("seed_release_files")
    on_exit(fn -> File.rm_rf(tmp_dir) end)

    script_path = Path.join(tmp_dir, "seed_release_files.escript")
    file_version = Escript.tzdata_release_file_version()
    release_file_name = "2025z.v#{file_version}.ets"
    release_file = Path.join([tmp_dir, "release_ets", release_file_name])
    release_payload = "release-data"

    File.mkdir_p!(tmp_dir)

    assert :ok =
             :escript.create(String.to_charlist(script_path), [
               :shebang,
               {:archive,
                [
                  {String.to_charlist("tzdata/priv/release_ets/#{release_file_name}"),
                   release_payload}
                ], []}
             ])

    assert :ok = Escript.seed_tzdata_release_files(tmp_dir, script_path)
    assert {:ok, ^release_payload} = File.read(release_file)
  end

  test "seed_tzdata_release_files fails when archive contains only incompatible release ETS files" do
    tmp_dir = unique_tmp_dir("missing_release_files")
    on_exit(fn -> File.rm_rf(tmp_dir) end)

    script_path = Path.join(tmp_dir, "missing_release_files.escript")
    incompatible_version = incompatible_file_version()
    incompatible_name = "2025z.v#{incompatible_version}.ets"
    incompatible_path = String.to_charlist("tzdata/priv/release_ets/#{incompatible_name}")

    File.mkdir_p!(tmp_dir)

    assert :ok =
             :escript.create(String.to_charlist(script_path), [
               :shebang,
               {:archive, [{incompatible_path, "incompatible-release"}], []}
             ])

    assert {:error, :missing_release_files} =
             Escript.seed_tzdata_release_files(tmp_dir, script_path)

    refute File.exists?(Path.join([tmp_dir, "release_ets", incompatible_name]))
  end

  test "seed_tzdata_release_files copies only compatible release ETS files" do
    tmp_dir = unique_tmp_dir("compatible_only")
    on_exit(fn -> File.rm_rf(tmp_dir) end)

    file_version = Escript.tzdata_release_file_version()
    incompatible_version = incompatible_file_version()
    compatible_name = "2025z.v#{file_version}.ets"
    incompatible_name = "2025z.v#{incompatible_version}.ets"
    compatible_payload = "compatible-release"

    script_path = Path.join(tmp_dir, "compatible_only.escript")
    compatible_archive_path = String.to_charlist("tzdata/priv/release_ets/#{compatible_name}")
    incompatible_archive_path = String.to_charlist("tzdata/priv/release_ets/#{incompatible_name}")

    File.mkdir_p!(tmp_dir)

    assert :ok =
             :escript.create(String.to_charlist(script_path), [
               :shebang,
               {:archive,
                [
                  {incompatible_archive_path, "incompatible-release"},
                  {compatible_archive_path, compatible_payload}
                ], []}
             ])

    assert :ok = Escript.seed_tzdata_release_files(tmp_dir, script_path)

    assert {:ok, ^compatible_payload} =
             File.read(Path.join([tmp_dir, "release_ets", compatible_name]))

    refute File.exists?(Path.join([tmp_dir, "release_ets", incompatible_name]))
  end

  test "seed_tzdata_release_files returns error when release target directory is invalid" do
    tmp_dir = unique_tmp_dir("invalid_release_target")
    on_exit(fn -> File.rm_rf(tmp_dir) end)

    file_version = Escript.tzdata_release_file_version()
    release_file_name = "2025z.v#{file_version}.ets"
    script_path = Path.join(tmp_dir, "invalid_release_target.escript")
    archive_path = String.to_charlist("tzdata/priv/release_ets/#{release_file_name}")

    File.mkdir_p!(tmp_dir)

    assert :ok =
             :escript.create(String.to_charlist(script_path), [
               :shebang,
               {:archive, [{archive_path, "release-data"}], []}
             ])

    assert {:error, {:release_dir_unavailable, :enotdir}} =
             Escript.seed_tzdata_release_files("/dev/null", script_path)
  end

  defp unique_tmp_dir(suffix) do
    Path.join(
      System.tmp_dir!(),
      "jido_command_escript_test_#{suffix}_#{System.unique_integer([:positive, :monotonic])}"
    )
  end

  defp incompatible_file_version do
    current = Escript.tzdata_release_file_version()
    if current == 1, do: 2, else: 1
  end
end
