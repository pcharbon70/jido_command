defmodule JidoCommand.CLITest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias JidoCommand.CLI

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

    def dispatch(command, params, context) do
      send(self(), {:runtime_dispatch, command, params, context})

      case command do
        "fail" -> {:error, :dispatch_error}
        _ -> {:ok, "invocation-123"}
      end
    end

    def reload do
      send(self(), :runtime_reload)
      :ok
    end

    def register_extension(path) do
      send(self(), {:runtime_register_extension, path})

      case path do
        "fail" -> {:error, :register_error}
        _ -> :ok
      end
    end
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

  test "register-extension calls runtime and prints ok status" do
    output =
      capture_io(fn ->
        assert :ok ==
                 CLI.main(
                   ["register-extension", "ext/.jido-extension/extension.json"],
                   fn code -> flunk("unexpected halt with #{code}") end,
                   RuntimeStub
                 )
      end)

    assert_receive {:runtime_register_extension, "ext/.jido-extension/extension.json"}, 500

    assert %{"status" => "ok", "manifest_path" => "ext/.jido-extension/extension.json"} ==
             Jason.decode!(output)
  end

  test "register-extension failure prints error and halts with 1" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:halt, 1} ==
                 catch_throw(
                   CLI.main(
                     ["register-extension", "fail"],
                     fn code -> throw({:halt, code}) end,
                     RuntimeStub
                   )
                 )
      end)

    assert_receive {:runtime_register_extension, "fail"}, 500
    assert stderr =~ "register-extension failed: :register_error"
  end
end
