defmodule JidoCommand.CLI do
  @moduledoc """
  Optimus-based CLI for invoking and listing registered commands.
  """

  @spec main([String.t()], (integer() -> no_return()), module()) :: :ok | no_return()
  @spec main([String.t()], (integer() -> no_return())) :: :ok | no_return()
  def main(argv, halt \\ &System.halt/1, runtime \\ JidoCommand) do
    parser = parser_spec()
    result = Optimus.parse(parser, argv)
    handle_parse_result(result, parser, halt, runtime)
  end

  defp handle_parse_result({:ok, [:list], _result}, _parser, _halt, runtime) do
    runtime.list_commands()
    |> Enum.each(&IO.puts/1)

    :ok
  end

  defp handle_parse_result({:ok, [:invoke], result}, _parser, halt, runtime) do
    handle_invoke(result, halt, runtime)
  end

  defp handle_parse_result({:ok, [:dispatch], result}, _parser, halt, runtime) do
    handle_dispatch(result, halt, runtime)
  end

  defp handle_parse_result({:ok, [:reload], _result}, _parser, halt, runtime) do
    handle_reload(halt, runtime)
  end

  defp handle_parse_result({:ok, [:register_command], result}, _parser, halt, runtime) do
    handle_register_command(result, halt, runtime)
  end

  defp handle_parse_result({:ok, [:unregister_command], result}, _parser, halt, runtime) do
    handle_unregister_command(result, halt, runtime)
  end

  defp handle_parse_result({:error, errors}, parser, halt, _runtime) do
    parser
    |> Optimus.Errors.format(errors)
    |> Enum.each(&IO.puts/1)

    halt.(1)
  end

  defp handle_parse_result({:error, subcommand_path, errors}, parser, halt, _runtime) do
    parser
    |> Optimus.Errors.format(subcommand_path, errors)
    |> Enum.each(&IO.puts/1)

    halt.(1)
  end

  defp handle_parse_result(:help, parser, halt, _runtime) do
    IO.puts(Optimus.help(parser))
    halt.(0)
  end

  defp handle_parse_result(:version, _parser, halt, _runtime) do
    IO.puts("jido_command 0.1.0")
    halt.(0)
  end

  defp handle_parse_result({:help, subcommand_path}, parser, halt, _runtime) do
    IO.puts(parser |> Optimus.Help.help(subcommand_path, 100) |> Enum.join("\n"))
    halt.(0)
  end

  defp handle_parse_result({:ok, _result}, parser, halt, _runtime) do
    IO.puts(Optimus.help(parser))
    halt.(1)
  end

  defp handle_invoke(result, halt, runtime) do
    command_name = result.args.command
    params = result.options.params || %{}
    context = result.options.context || %{}
    invocation_id = result.options.invocation_id

    case invoke_runtime(runtime, command_name, params, context, invocation_id) do
      {:ok, value} ->
        IO.puts(Jason.encode!(value, pretty: true))
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "invoke failed: #{inspect(reason)}")
        halt.(1)
    end
  end

  defp handle_dispatch(result, halt, runtime) do
    command_name = result.args.command
    params = result.options.params || %{}
    context = result.options.context || %{}
    invocation_id = result.options.invocation_id

    case dispatch_runtime(runtime, command_name, params, context, invocation_id) do
      {:ok, invocation_id} ->
        IO.puts(Jason.encode!(%{"invocation_id" => invocation_id}, pretty: true))
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "dispatch failed: #{inspect(reason)}")
        halt.(1)
    end
  end

  defp handle_reload(halt, runtime) do
    case runtime.reload() do
      :ok ->
        IO.puts(Jason.encode!(%{"status" => "ok"}))
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "reload failed: #{inspect(reason)}")
        halt.(1)
    end
  end

  defp handle_register_command(result, halt, runtime) do
    command_path = result.args.command_path

    case runtime.register_command(command_path) do
      :ok ->
        IO.puts(Jason.encode!(%{"status" => "ok", "command_path" => command_path}))
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "register-command failed: #{inspect(reason)}")
        halt.(1)
    end
  end

  defp handle_unregister_command(result, halt, runtime) do
    command_name = result.args.command_name

    case runtime.unregister_command(command_name) do
      :ok ->
        IO.puts(Jason.encode!(%{"status" => "ok", "command_name" => command_name}))
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "unregister-command failed: #{inspect(reason)}")
        halt.(1)
    end
  end

  defp parser_spec do
    Optimus.new!(
      name: "jido_command",
      description: "Signal-driven command runtime",
      version: "0.1.0",
      author: "JidoCommand",
      about: "Invoke markdown-defined commands",
      allow_unknown_args: false,
      parse_double_dash: true,
      subcommands: [
        list: [
          name: "list",
          about: "List loaded command names"
        ],
        invoke: [
          name: "invoke",
          about: "Invoke a command",
          args: [
            command: [
              value_name: "COMMAND",
              help: "Command name",
              required: true,
              parser: :string
            ]
          ],
          options: [
            params: [
              value_name: "JSON",
              long: "--params",
              short: "-p",
              help: "JSON object with command params",
              required: false,
              parser: &parse_json_object/1,
              default: %{}
            ],
            context: [
              value_name: "JSON",
              long: "--context",
              short: "-c",
              help: "JSON object with invoke context",
              required: false,
              parser: &parse_json_object/1,
              default: %{}
            ],
            invocation_id: [
              value_name: "ID",
              long: "--invocation-id",
              help: "Optional invocation id override",
              required: false,
              parser: &parse_nonempty_string/1
            ]
          ]
        ],
        dispatch: [
          name: "dispatch",
          about: "Publish a command.invoke signal",
          args: [
            command: [
              value_name: "COMMAND",
              help: "Command name",
              required: true,
              parser: :string
            ]
          ],
          options: [
            params: [
              value_name: "JSON",
              long: "--params",
              short: "-p",
              help: "JSON object with command params",
              required: false,
              parser: &parse_json_object/1,
              default: %{}
            ],
            context: [
              value_name: "JSON",
              long: "--context",
              short: "-c",
              help: "JSON object with dispatch context",
              required: false,
              parser: &parse_json_object/1,
              default: %{}
            ],
            invocation_id: [
              value_name: "ID",
              long: "--invocation-id",
              help: "Optional invocation id override",
              required: false,
              parser: &parse_nonempty_string/1
            ]
          ]
        ],
        reload: [
          name: "reload",
          about: "Reload command registry from configured roots"
        ],
        register_command: [
          name: "register-command",
          about: "Register one command markdown file at runtime",
          args: [
            command_path: [
              value_name: "COMMAND_PATH",
              help: "Path to command markdown file",
              required: true,
              parser: :string
            ]
          ]
        ],
        unregister_command: [
          name: "unregister-command",
          about: "Unregister one command by name at runtime",
          args: [
            command_name: [
              value_name: "COMMAND_NAME",
              help: "Registered command name",
              required: true,
              parser: :string
            ]
          ]
        ]
      ]
    )
  end

  defp parse_json_object(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:ok, _} -> {:error, "must be a JSON object"}
      {:error, reason} -> {:error, "invalid JSON: #{Exception.message(reason)}"}
    end
  end

  defp parse_nonempty_string(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:error, "must be a non-empty string"}
    else
      {:ok, trimmed}
    end
  end

  defp parse_nonempty_string(_), do: {:error, "must be a non-empty string"}

  defp invoke_runtime(runtime, command_name, params, context, nil) do
    runtime.invoke(command_name, params, context)
  end

  defp invoke_runtime(runtime, command_name, params, context, invocation_id) do
    if function_exported?(runtime, :invoke, 4) do
      runtime.invoke(command_name, params, context, invocation_id: invocation_id)
    else
      runtime.invoke(command_name, params, Map.put(context, :invocation_id, invocation_id))
    end
  end

  defp dispatch_runtime(runtime, command_name, params, context, nil) do
    runtime.dispatch(command_name, params, context)
  end

  defp dispatch_runtime(runtime, command_name, params, context, invocation_id) do
    if function_exported?(runtime, :dispatch, 4) do
      runtime.dispatch(command_name, params, context, invocation_id: invocation_id)
    else
      runtime.dispatch(command_name, params, Map.put(context, :invocation_id, invocation_id))
    end
  end
end
