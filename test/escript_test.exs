defmodule Jido.Code.Command.EscriptTest do
  use ExUnit.Case, async: true

  alias Jido.Code.Command.Escript

  test "seed_tzdata_release_files copies release ETS files from an escript archive" do
    tmp_dir = unique_tmp_dir("seed_release_files")
    on_exit(fn -> File.rm_rf(tmp_dir) end)

    script_path = Path.join(tmp_dir, "seed_release_files.escript")
    release_file = Path.join([tmp_dir, "release_ets", "2025z.v2.ets"])
    release_payload = "release-data"

    File.mkdir_p!(tmp_dir)

    assert :ok =
             :escript.create(String.to_charlist(script_path), [
               :shebang,
               {:archive, [{~c"tzdata/priv/release_ets/2025z.v2.ets", release_payload}], []}
             ])

    assert :ok = Escript.seed_tzdata_release_files(tmp_dir, script_path)
    assert {:ok, ^release_payload} = File.read(release_file)
  end

  test "seed_tzdata_release_files fails when archive contains no release ETS files" do
    tmp_dir = unique_tmp_dir("missing_release_files")
    on_exit(fn -> File.rm_rf(tmp_dir) end)

    script_path = Path.join(tmp_dir, "missing_release_files.escript")

    File.mkdir_p!(tmp_dir)

    assert :ok =
             :escript.create(String.to_charlist(script_path), [
               :shebang,
               {:archive, [{~c"other/path/file.txt", "not-a-release"}], []}
             ])

    assert {:error, :missing_release_files} =
             Escript.seed_tzdata_release_files(tmp_dir, script_path)
  end

  defp unique_tmp_dir(suffix) do
    Path.join(
      System.tmp_dir!(),
      "jido_command_escript_test_#{suffix}_#{System.unique_integer([:positive, :monotonic])}"
    )
  end
end
