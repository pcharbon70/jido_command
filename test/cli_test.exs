defmodule Jido.Code.Command.CLITest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Jido.Code.Command.CLI

  defmodule RuntimeStub do
    def list_commands do
      ["alpha", "beta"]
    end

    def invoke(command, params, context) do
      send(self(), {:runtime_invoke, command, params, context})

      case command do
        "fail" -> {:error, :invoke_error}
        _ -> {:ok, %{"ok" => true, "command" => command}}
      end
    end

    def invoke(command, params, context, opts) do
      send(self(), {:runtime_invoke_with_opts, command, params, context, opts})

      case command do
        "fail" -> {:error, :invoke_error}
        _ -> {:ok, %{"ok" => true, "command" => command, "invocation_id" => opts[:invocation_id]}}
      end
    end

    def dispatch(command, params, context) do
      send(self(), {:runtime_dispatch, command, params, context})

      case command do
        "fail" -> {:error, :dispatch_error}
        _ -> {:ok, "invocation-123"}
      end
    end

    def dispatch(command, params, context, opts) do
      send(self(), {:runtime_dispatch_with_opts, command, params, context, opts})

      case command do
        "fail" -> {:error, :dispatch_error}
        _ -> {:ok, opts[:invocation_id] || "invocation-123"}
      end
    end

    def reload do
      send(self(), :runtime_reload)
      :ok
    end

    def register_command(command_path) do
      send(self(), {:runtime_register_command, command_path})

      case command_path do
        "fail" -> {:error, :register_command_error}
        _ -> :ok
      end
    end

    def unregister_command(command_name) do
      send(self(), {:runtime_unregister_command, command_name})

      case command_name do
        "missing" -> {:error, :not_found}
        _ -> :ok
      end
    end
  end

  defmodule FailingListRuntimeStub do
    def list_commands do
      {:error, {:registry_unavailable, :noproc}}
    end
  end

  defmodule FailingReloadRuntimeStub do
    def reload do
      send(self(), :runtime_reload_failed)
      {:error, :reload_error}
    end
  end

  defmodule FailingRegisterCommandRuntimeStub do
    def register_command(command_path) do
      send(self(), {:runtime_register_command_failed, command_path})
      {:error, :register_command_error}
    end
  end

  defmodule FailingUnregisterCommandRuntimeStub do
    def unregister_command(command_name) do
      send(self(), {:runtime_unregister_command_failed, command_name})
      {:error, :unregister_command_error}
    end
  end

  defmodule InvalidListResponseRuntimeStub do
    def list_commands do
      [123]
    end
  end

  defmodule InvalidInvokeResponseRuntimeStub do
    def invoke(_command, _params, _context), do: :ok
  end

  defmodule InvalidDispatchResponseRuntimeStub do
    def dispatch(_command, _params, _context), do: {:ok, 123}
  end

  defmodule InvalidReloadResponseRuntimeStub do
    def reload, do: {:ok, :unexpected}
  end

  defmodule InvalidRegisterCommandResponseRuntimeStub do
    def register_command(_command_path), do: {:ok, :unexpected}
  end

  defmodule InvalidUnregisterCommandResponseRuntimeStub do
    def unregister_command(_command_name), do: {:ok, :unexpected}
  end

  defmodule RaisingListRuntimeStub do
    def list_commands, do: raise("list boom")
  end

  defmodule RaisingInvokeRuntimeStub do
    def invoke(_command, _params, _context), do: raise("invoke boom")
  end

  defmodule ThrowingInvokeRuntimeStub do
    def invoke(_command, _params, _context), do: throw(:invoke_boom)
  end

  defmodule RaisingDispatchRuntimeStub do
    def dispatch(_command, _params, _context), do: raise("dispatch boom")
  end

  defmodule RaisingReloadRuntimeStub do
    def reload, do: raise("reload boom")
  end

  defmodule RaisingRegisterCommandRuntimeStub do
    def register_command(_command_path), do: raise("register boom")
  end

  defmodule RaisingUnregisterCommandRuntimeStub do
    def unregister_command(_command_name), do: raise("unregister boom")
  end

  defp write_temp_json_file!(content) when is_binary(content) do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido_command_cli_#{System.unique_integer([:positive, :monotonic])}.json"
      )

    File.write!(path, content)
    path
  end

  test "list prints loaded command names" do
    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   ["list"],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert output == "alpha\nbeta\n"
  end

  test "list failure prints error and halts with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["list"],
                     fn code -> throw({:halt, code}) end,
                     FailingListRuntimeStub
                   )
                 )
      end)

    assert stderr =~ "list failed: {:registry_unavailable, :noproc}"
  end

  test "list invalid response prints error and halts with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["list"],
                     fn code -> throw({:halt, code}) end,
                     InvalidListResponseRuntimeStub
                   )
                 )
      end)

    assert stderr =~ "list failed: invalid runtime response: [123]"
  end

  test "list runtime exceptions print error and halt with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["list"],
                     fn code -> throw({:halt, code}) end,
                     RaisingListRuntimeStub
                   )
                 )
      end)

    assert stderr =~ "list failed: runtime exception: list boom"
  end

  test "dispatch publishes via runtime and prints invocation id" do
    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   [
                     "dispatch",
                     "demo",
                     "--params",
                     ~s({"x":1}),
                     "--context",
                     ~s({"source":"cli"})
                   ],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_dispatch, "demo", %{"x" => 1}, %{"source" => "cli"}}, 500
    assert %{"invocation_id" => "invocation-123"} == Jason.decode!(output)
  end

  test "dispatch supports params/context file options with inline overrides" do
    params_path = write_temp_json_file!(~s({"x":1,"shared":"file"}))
    context_path = write_temp_json_file!(~s({"source":"file","shared":"file"}))

    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   [
                     "dispatch",
                     "demo",
                     "--params-file",
                     params_path,
                     "--params",
                     ~s({"shared":"inline"}),
                     "--context-file",
                     context_path,
                     "--context",
                     ~s({"shared":"inline"})
                   ],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_dispatch, "demo", params, context}, 500
    assert params == %{"x" => 1, "shared" => "inline"}
    assert context == %{"source" => "file", "shared" => "inline"}
    assert %{"invocation_id" => "invocation-123"} == Jason.decode!(output)
  end

  test "invoke uses runtime module injection" do
    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   ["invoke", "review", "--params", ~s({"target":"README.md"})],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_invoke, "review", %{"target" => "README.md"}, %{}}, 500
    assert %{"ok" => true, "command" => "review"} == Jason.decode!(output)
  end

  test "invoke supports params/context file options with inline overrides" do
    params_path = write_temp_json_file!(~s({"target":"from-file.md","shared":"file"}))
    context_path = write_temp_json_file!(~s({"source":"file","shared":"file"}))

    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   [
                     "invoke",
                     "review",
                     "--params-file",
                     params_path,
                     "--params",
                     ~s({"shared":"inline"}),
                     "--context-file",
                     context_path,
                     "--context",
                     ~s({"shared":"inline"})
                   ],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_invoke, "review", params, context}, 500
    assert params == %{"target" => "from-file.md", "shared" => "inline"}
    assert context == %{"source" => "file", "shared" => "inline"}
    assert %{"ok" => true, "command" => "review"} == Jason.decode!(output)
  end

  test "top-level command name invokes runtime command execution" do
    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   ["review", "--params", ~s({"target":"README.md"})],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_invoke, "review", %{"target" => "README.md"}, %{}}, 500
    assert %{"ok" => true, "command" => "review"} == Jason.decode!(output)
  end

  test "top-level command name with invoke options invokes runtime command execution" do
    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   ["review", "--invocation-id", "invoke-123"],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_invoke_with_opts, "review", %{}, %{}, opts}, 500
    assert opts[:invocation_id] == "invoke-123"

    assert %{"ok" => true, "command" => "review", "invocation_id" => "invoke-123"} ==
             Jason.decode!(output)
  end

  test "top-level -- disambiguates command names that match CLI subcommands" do
    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   ["--", "list", "--target-file", "README.md"],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_invoke, "list", %{"target_file" => "README.md"}, %{}}, 500
    assert %{"ok" => true, "command" => "list"} == Jason.decode!(output)
  end

  test "top-level command name maps shorthand options into invoke params" do
    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   [
                     "review",
                     "--target-file",
                     "README.md",
                     "--max-results",
                     "10",
                     "--dry-run",
                     "--score=0.75",
                     "--meta",
                     ~s({"x":1})
                   ],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_invoke, "review", params, %{}}, 500
    assert params["target_file"] == "README.md"
    assert params["max_results"] == 10
    assert params["dry_run"] == true
    assert params["score"] == 0.75
    assert params["meta"] == %{"x" => 1}
    assert %{"ok" => true, "command" => "review"} == Jason.decode!(output)
  end

  test "top-level command name merges --params with shorthand params in argument order" do
    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   [
                     "review",
                     "--count",
                     "1",
                     "--params",
                     ~s({"target_file":"lib/foo.ex","count":2}),
                     "--count",
                     "3"
                   ],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_invoke, "review", params, %{}}, 500
    assert params["target_file"] == "lib/foo.ex"
    assert params["count"] == 3
    assert %{"ok" => true, "command" => "review"} == Jason.decode!(output)
  end

  test "top-level command name supports params/context file options with long equals syntax" do
    params_path = write_temp_json_file!(~s({"target_file":"from-file.md","count":1}))
    context_path = write_temp_json_file!(~s({"source":"file","trace":"file"}))

    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   [
                     "review",
                     "--params-file=#{params_path}",
                     "--count",
                     "3",
                     "--context-file=#{context_path}",
                     "--context",
                     ~s({"trace":"inline"})
                   ],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_invoke, "review", params, context}, 500
    assert params == %{"target_file" => "from-file.md", "count" => 3}
    assert context == %{"source" => "file", "trace" => "inline"}
    assert %{"ok" => true, "command" => "review"} == Jason.decode!(output)
  end

  test "top-level command name keeps inline params/context precedence regardless option order" do
    params_path = write_temp_json_file!(~s({"count":1,"shared":"file","file_only":"yes"}))
    context_path = write_temp_json_file!(~s({"shared":"file","source":"file"}))

    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   [
                     "review",
                     "--params",
                     ~s({"shared":"inline"}),
                     "--count",
                     "3",
                     "--params-file",
                     params_path,
                     "--context",
                     ~s({"shared":"inline"}),
                     "--context-file",
                     context_path
                   ],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_invoke, "review", params, context}, 500
    assert params == %{"count" => 3, "shared" => "inline", "file_only" => "yes"}
    assert context == %{"shared" => "inline", "source" => "file"}
    assert %{"ok" => true, "command" => "review"} == Jason.decode!(output)
  end

  test "top-level command name supports invoke runtime options with shorthand params" do
    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   [
                     "review",
                     "--context",
                     ~s({"source":"cli"}),
                     "--bus",
                     ":custom_bus",
                     "--invocation-id",
                     "invoke-321",
                     "--target-file",
                     "README.md"
                   ],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_invoke_with_opts, "review", params, context, opts}, 500
    assert params == %{"target_file" => "README.md"}
    assert context == %{"source" => "cli"}
    assert opts[:bus] == ":custom_bus"
    assert opts[:invocation_id] == "invoke-321"

    assert %{"ok" => true, "command" => "review", "invocation_id" => "invoke-321"} ==
             Jason.decode!(output)
  end

  test "invoke passes invocation-id option to runtime when available" do
    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   ["invoke", "review", "--invocation-id", "invoke-123"],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_invoke_with_opts, "review", %{}, %{}, opts}, 500
    assert opts[:invocation_id] == "invoke-123"

    assert %{"ok" => true, "command" => "review", "invocation_id" => "invoke-123"} ==
             Jason.decode!(output)
  end

  test "invoke passes bus option to runtime when available" do
    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   ["invoke", "review", "--bus", ":custom_bus"],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_invoke_with_opts, "review", %{}, %{}, opts}, 500
    assert opts[:bus] == ":custom_bus"
    assert opts[:invocation_id] == nil

    assert %{"ok" => true, "command" => "review", "invocation_id" => nil} ==
             Jason.decode!(output)
  end

  test "invoke invalid response prints error and halts with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["invoke", "review"],
                     fn code -> throw({:halt, code}) end,
                     InvalidInvokeResponseRuntimeStub
                   )
                 )
      end)

    assert stderr =~ "invoke failed: invalid runtime response: :ok"
  end

  test "invoke runtime exceptions print error and halt with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["invoke", "review"],
                     fn code -> throw({:halt, code}) end,
                     RaisingInvokeRuntimeStub
                   )
                 )
      end)

    assert stderr =~ "invoke failed: runtime exception: invoke boom"
  end

  test "invoke runtime throws print error and halt with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["invoke", "review"],
                     fn code -> throw({:halt, code}) end,
                     ThrowingInvokeRuntimeStub
                   )
                 )
      end)

    assert stderr =~ "invoke failed: runtime throw: {:throw, :invoke_boom}"
  end

  test "invoke params-file read failure prints error and halts with 1" do
    missing_path =
      Path.join(
        System.tmp_dir!(),
        "jido_command_cli_missing_#{System.unique_integer([:positive, :monotonic])}.json"
      )

    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["invoke", "review", "--params-file", missing_path],
                     fn code -> throw({:halt, code}) end,
                     RuntimeStub
                   )
                 )
      end)

    assert stderr =~ "invoke failed: invalid --params-file: unable to read #{missing_path}:"
    refute_receive {:runtime_invoke, _, _, _}
    refute_receive {:runtime_invoke_with_opts, _, _, _, _}
  end

  test "dispatch failure prints error and halts with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["dispatch", "fail"],
                     fn code -> throw({:halt, code}) end,
                     RuntimeStub
                   )
                 )
      end)

    assert_receive {:runtime_dispatch, "fail", %{}, %{}}, 500
    assert stderr =~ "dispatch failed: :dispatch_error"
  end

  test "dispatch passes invocation-id option to runtime when available" do
    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   ["dispatch", "demo", "--invocation-id", "dispatch-123"],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_dispatch_with_opts, "demo", %{}, %{}, opts}, 500
    assert opts[:invocation_id] == "dispatch-123"
    assert %{"invocation_id" => "dispatch-123"} == Jason.decode!(output)
  end

  test "dispatch passes bus option to runtime when available" do
    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   ["dispatch", "demo", "--bus", ":custom_bus"],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_dispatch_with_opts, "demo", %{}, %{}, opts}, 500
    assert opts[:bus] == ":custom_bus"
    assert opts[:invocation_id] == nil
    assert %{"invocation_id" => "invocation-123"} == Jason.decode!(output)
  end

  test "dispatch invalid response prints error and halts with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["dispatch", "demo"],
                     fn code -> throw({:halt, code}) end,
                     InvalidDispatchResponseRuntimeStub
                   )
                 )
      end)

    assert stderr =~ "dispatch failed: invalid runtime response: {:ok, 123}"
  end

  test "dispatch runtime exceptions print error and halt with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["dispatch", "demo"],
                     fn code -> throw({:halt, code}) end,
                     RaisingDispatchRuntimeStub
                   )
                 )
      end)

    assert stderr =~ "dispatch failed: runtime exception: dispatch boom"
  end

  test "reload calls runtime and prints ok status" do
    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   ["reload"],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive :runtime_reload, 500
    assert %{"status" => "ok"} == Jason.decode!(output)
  end

  test "reload failure prints error and halts with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["reload"],
                     fn code -> throw({:halt, code}) end,
                     FailingReloadRuntimeStub
                   )
                 )
      end)

    assert_receive :runtime_reload_failed, 500
    assert stderr =~ "reload failed: :reload_error"
  end

  test "reload invalid response prints error and halts with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["reload"],
                     fn code -> throw({:halt, code}) end,
                     InvalidReloadResponseRuntimeStub
                   )
                 )
      end)

    assert stderr =~ "reload failed: invalid runtime response: {:ok, :unexpected}"
  end

  test "reload runtime exceptions print error and halt with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["reload"],
                     fn code -> throw({:halt, code}) end,
                     RaisingReloadRuntimeStub
                   )
                 )
      end)

    assert stderr =~ "reload failed: runtime exception: reload boom"
  end

  test "register-command calls runtime and prints ok status" do
    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   ["register-command", "commands/new.md"],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_register_command, "commands/new.md"}, 500
    assert %{"status" => "ok", "command_path" => "commands/new.md"} == Jason.decode!(output)
  end

  test "register-command failure prints error and halts with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["register-command", "commands/fail.md"],
                     fn code -> throw({:halt, code}) end,
                     FailingRegisterCommandRuntimeStub
                   )
                 )
      end)

    assert_receive {:runtime_register_command_failed, "commands/fail.md"}, 500
    assert stderr =~ "register-command failed: :register_command_error"
  end

  test "register-command invalid response prints error and halts with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["register-command", "commands/new.md"],
                     fn code -> throw({:halt, code}) end,
                     InvalidRegisterCommandResponseRuntimeStub
                   )
                 )
      end)

    assert stderr =~
             "register-command failed: invalid runtime response: {:ok, :unexpected}"
  end

  test "register-command runtime exceptions print error and halt with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["register-command", "commands/new.md"],
                     fn code -> throw({:halt, code}) end,
                     RaisingRegisterCommandRuntimeStub
                   )
                 )
      end)

    assert stderr =~ "register-command failed: runtime exception: register boom"
  end

  test "unregister-command calls runtime and prints ok status" do
    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   ["unregister-command", "review"],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_unregister_command, "review"}, 500
    assert %{"status" => "ok", "command_name" => "review"} == Jason.decode!(output)
  end

  test "unregister-command failure prints error and halts with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["unregister-command", "review"],
                     fn code -> throw({:halt, code}) end,
                     FailingUnregisterCommandRuntimeStub
                   )
                 )
      end)

    assert_receive {:runtime_unregister_command_failed, "review"}, 500
    assert stderr =~ "unregister-command failed: :unregister_command_error"
  end

  test "unregister-command invalid response prints error and halts with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["unregister-command", "review"],
                     fn code -> throw({:halt, code}) end,
                     InvalidUnregisterCommandResponseRuntimeStub
                   )
                 )
      end)

    assert stderr =~
             "unregister-command failed: invalid runtime response: {:ok, :unexpected}"
  end

  test "unregister-command runtime exceptions print error and halt with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["unregister-command", "review"],
                     fn code -> throw({:halt, code}) end,
                     RaisingUnregisterCommandRuntimeStub
                   )
                 )
      end)

    assert stderr =~ "unregister-command failed: runtime exception: unregister boom"
  end

  test "top-level parse errors print to stderr and halt with 1" do
    stderr =
      capture_io(:stderr, fn ->
        stdout =
          capture_io(fn ->
            assert {:halt, 1} ==
                     catch_throw(
                       CLI.main(
                         ["--unknown-option"],
                         fn code -> throw({:halt, code}) end,
                         RuntimeStub
                       )
                     )
          end)

        send(self(), {:stdout, stdout})
      end)

    assert_receive {:stdout, ""}
    assert stderr != ""
  end

  test "top-level blank command name halts with parse error" do
    stderr =
      capture_io(:stderr, fn ->
        stdout =
          capture_io(fn ->
            assert {:halt, 1} ==
                     catch_throw(
                       CLI.main(
                         ["   "],
                         fn code -> throw({:halt, code}) end,
                         RuntimeStub
                       )
                     )
          end)

        send(self(), {:stdout, stdout})
      end)

    assert_receive {:stdout, ""}
    assert stderr != ""
  end

  test "top-level command name with missing reserved option value halts with parse error" do
    stderr =
      capture_io(:stderr, fn ->
        stdout =
          capture_io(fn ->
            assert {:halt, 1} ==
                     catch_throw(
                       CLI.main(
                         ["review", "--invocation-id"],
                         fn code -> throw({:halt, code}) end,
                         RuntimeStub
                       )
                     )
          end)

        send(self(), {:stdout, stdout})
      end)

    assert_receive {:stdout, ""}
    assert stderr =~ "invalid --invocation-id: missing value"
  end

  test "legacy --command entrypoint halts with parse error" do
    stderr =
      capture_io(:stderr, fn ->
        stdout =
          capture_io(fn ->
            assert {:halt, 1} ==
                     catch_throw(
                       CLI.main(
                         ["--command", "review"],
                         fn code -> throw({:halt, code}) end,
                         RuntimeStub
                       )
                     )
          end)

        send(self(), {:stdout, stdout})
      end)

    assert_receive {:stdout, ""}

    assert stderr =~
             "legacy --command entrypoint is not supported; use: command <command-name> [options]"
  end

  test "top-level -- without command name halts with parse error" do
    stderr =
      capture_io(:stderr, fn ->
        stdout =
          capture_io(fn ->
            assert {:halt, 1} ==
                     catch_throw(
                       CLI.main(
                         ["--"],
                         fn code -> throw({:halt, code}) end,
                         RuntimeStub
                       )
                     )
          end)

        send(self(), {:stdout, stdout})
      end)

    assert_receive {:stdout, ""}
    assert stderr =~ "invalid command invocation: missing command name after --"
  end

  test "subcommand parse errors print to stderr and halt with 1" do
    stderr =
      capture_io(:stderr, fn ->
        stdout =
          capture_io(fn ->
            assert {:halt, 1} ==
                     catch_throw(
                       CLI.main(
                         ["invoke", "review", "--params", "{not-json}"],
                         fn code -> throw({:halt, code}) end,
                         RuntimeStub
                       )
                     )
          end)

        send(self(), {:stdout, stdout})
      end)

    assert_receive {:stdout, ""}
    assert stderr =~ "invalid JSON"
  end

  test "subcommand parse errors for blank bus values print to stderr and halt with 1" do
    stderr =
      capture_io(:stderr, fn ->
        stdout =
          capture_io(fn ->
            assert {:halt, 1} ==
                     catch_throw(
                       CLI.main(
                         ["dispatch", "review", "--bus", "   "],
                         fn code -> throw({:halt, code}) end,
                         RuntimeStub
                       )
                     )
          end)

        send(self(), {:stdout, stdout})
      end)

    assert_receive {:stdout, ""}
    assert stderr =~ "must be a non-empty string"
  end
end
