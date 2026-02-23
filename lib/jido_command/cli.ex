defmodule Jido.Code.Command.CLI do
  @moduledoc """
  Optimus-based CLI for invoking and listing registered commands.

  Supports default command invocation form: `<command-name> [invoke opts]`.
  Use `-- <command-name> ...` to disambiguate names that match CLI subcommands.
  """

  @cli_subcommands ~w(list invoke dispatch reload register-command unregister-command)

  @spec main([String.t()], (integer() -> no_return()), module()) :: :ok | no_return()
  @spec main([String.t()], (integer() -> no_return())) :: :ok | no_return()
  def main(argv, halt \\ &System.halt/1, runtime \\ Jido.Code.Command) do
    case normalize_default_command_invocation(argv) do
      {:ok, normalized_argv} ->
        parser = parser_spec()
        result = Optimus.parse(parser, normalized_argv)
        handle_parse_result(result, parser, halt, runtime)

      {:error, reason} ->
        IO.puts(:stderr, reason)
        halt.(1)
    end
  end

  defp normalize_default_command_invocation(["--"]) do
    {:error, "invalid command invocation: missing command name after --"}
  end

  defp normalize_default_command_invocation(["--", command | rest]) when is_binary(command) do
    case parse_top_level_command_name(command) do
      {:ok, normalized_command} -> rewrite_top_level_command_alias(normalized_command, rest)
      :error -> {:error, "invalid command invocation: missing command name after --"}
    end
  end

  defp normalize_default_command_invocation([first | _rest] = argv) when is_binary(first) do
    cond do
      known_cli_subcommand?(first) ->
        {:ok, argv}

      String.starts_with?(first, "-") ->
        {:ok, argv}

      true ->
        case parse_top_level_command_name(first) do
          {:ok, normalized_command} ->
            rewrite_top_level_command_alias(normalized_command, tl(argv))

          :error ->
            {:ok, ["invoke"]}
        end
    end
  end

  defp normalize_default_command_invocation(argv), do: {:ok, argv}

  defp known_cli_subcommand?(name) when is_binary(name), do: name in @cli_subcommands

  defp rewrite_top_level_command_alias(command, rest)
       when is_binary(command) and is_list(rest) do
    with {:ok, parsed} <- parse_top_level_command_options(rest) do
      {:ok, build_invoke_alias_argv(command, parsed)}
    end
  end

  defp parse_top_level_command_options(tokens) when is_list(tokens) do
    do_parse_top_level_command_options(tokens, %{
      params: %{},
      context: %{},
      invocation_id: nil,
      bus: nil
    })
  end

  defp do_parse_top_level_command_options([], state), do: {:ok, state}

  defp do_parse_top_level_command_options(["--params" | rest], state) do
    with {:ok, value, remaining} <- take_required_option_value("--params", rest),
         {:ok, params} <- parse_json_option("--params", value) do
      next_state = %{state | params: Map.merge(state.params, params)}
      do_parse_top_level_command_options(remaining, next_state)
    end
  end

  defp do_parse_top_level_command_options(["-p" | rest], state) do
    with {:ok, value, remaining} <- take_required_option_value("-p", rest),
         {:ok, params} <- parse_json_option("-p", value) do
      next_state = %{state | params: Map.merge(state.params, params)}
      do_parse_top_level_command_options(remaining, next_state)
    end
  end

  defp do_parse_top_level_command_options([<<"--params=", value::binary>> | rest], state) do
    with {:ok, params} <- parse_json_option("--params", value) do
      next_state = %{state | params: Map.merge(state.params, params)}
      do_parse_top_level_command_options(rest, next_state)
    end
  end

  defp do_parse_top_level_command_options(["--context" | rest], state) do
    with {:ok, value, remaining} <- take_required_option_value("--context", rest),
         {:ok, context} <- parse_json_option("--context", value) do
      next_state = %{state | context: Map.merge(state.context, context)}
      do_parse_top_level_command_options(remaining, next_state)
    end
  end

  defp do_parse_top_level_command_options(["-c" | rest], state) do
    with {:ok, value, remaining} <- take_required_option_value("-c", rest),
         {:ok, context} <- parse_json_option("-c", value) do
      next_state = %{state | context: Map.merge(state.context, context)}
      do_parse_top_level_command_options(remaining, next_state)
    end
  end

  defp do_parse_top_level_command_options([<<"--context=", value::binary>> | rest], state) do
    with {:ok, context} <- parse_json_option("--context", value) do
      next_state = %{state | context: Map.merge(state.context, context)}
      do_parse_top_level_command_options(rest, next_state)
    end
  end

  defp do_parse_top_level_command_options(["--invocation-id" | rest], state) do
    with {:ok, value, remaining} <- take_required_option_value("--invocation-id", rest),
         {:ok, invocation_id} <- parse_string_option("--invocation-id", value) do
      do_parse_top_level_command_options(remaining, %{state | invocation_id: invocation_id})
    end
  end

  defp do_parse_top_level_command_options([<<"--invocation-id=", value::binary>> | rest], state) do
    with {:ok, invocation_id} <- parse_string_option("--invocation-id", value) do
      do_parse_top_level_command_options(rest, %{state | invocation_id: invocation_id})
    end
  end

  defp do_parse_top_level_command_options(["--bus" | rest], state) do
    with {:ok, value, remaining} <- take_required_option_value("--bus", rest),
         {:ok, bus} <- parse_string_option("--bus", value) do
      do_parse_top_level_command_options(remaining, %{state | bus: bus})
    end
  end

  defp do_parse_top_level_command_options([<<"--bus=", value::binary>> | rest], state) do
    with {:ok, bus} <- parse_string_option("--bus", value) do
      do_parse_top_level_command_options(rest, %{state | bus: bus})
    end
  end

  defp do_parse_top_level_command_options([<<"--", raw_option::binary>> | rest], state) do
    with {:ok, key, value, remaining} <- parse_param_option(raw_option, rest) do
      params = Map.put(state.params, key, value)
      do_parse_top_level_command_options(remaining, %{state | params: params})
    end
  end

  defp do_parse_top_level_command_options([option | _rest], _state) when is_binary(option) do
    {:error, "invalid command option: #{option}"}
  end

  defp take_required_option_value(option, []), do: {:error, "invalid #{option}: missing value"}

  defp take_required_option_value(option, [value | rest])
       when is_binary(option) and is_binary(value) do
    if option_boundary_token?(value) do
      {:error, "invalid #{option}: missing value"}
    else
      {:ok, value, rest}
    end
  end

  defp parse_json_option(option, value) when is_binary(option) and is_binary(value) do
    case parse_json_object(value) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, "invalid #{option}: #{reason}"}
    end
  end

  defp parse_string_option(option, value) when is_binary(option) and is_binary(value) do
    case parse_nonempty_string(value) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, "invalid #{option}: #{reason}"}
    end
  end

  defp option_boundary_token?(token) when is_binary(token) do
    String.starts_with?(token, "--") or token in ["-p", "-c"]
  end

  defp parse_param_option(raw_option, rest)
       when is_binary(raw_option) and is_list(rest) do
    case String.split(raw_option, "=", parts: 2) do
      [raw_key, raw_value] -> parse_param_with_explicit_value(raw_key, raw_value, rest)
      [raw_key] -> parse_param_with_optional_value(raw_key, rest)
    end
  end

  defp parse_param_with_explicit_value(raw_key, raw_value, rest)
       when is_binary(raw_key) and is_binary(raw_value) and is_list(rest) do
    with {:ok, key} <- normalize_param_key(raw_key) do
      {:ok, key, parse_param_value(raw_value), rest}
    end
  end

  defp parse_param_with_optional_value(raw_key, rest)
       when is_binary(raw_key) and is_list(rest) do
    with {:ok, key} <- normalize_param_key(raw_key) do
      {value, remaining} = parse_optional_param_value(rest)
      {:ok, key, value, remaining}
    end
  end

  defp parse_optional_param_value([next | remaining]) when is_binary(next) do
    if option_boundary_token?(next) do
      {true, [next | remaining]}
    else
      {parse_param_value(next), remaining}
    end
  end

  defp parse_optional_param_value(rest) when is_list(rest), do: {true, rest}

  defp normalize_param_key(raw_key) when is_binary(raw_key) do
    trimmed = String.trim(raw_key)

    if trimmed == "" do
      {:error, "invalid command option: --"}
    else
      {:ok, String.replace(trimmed, "-", "_")}
    end
  end

  defp parse_param_value(value) when is_binary(value) do
    trimmed = String.trim(value)

    case Jason.decode(trimmed) do
      {:ok, parsed} -> parsed
      {:error, _reason} -> trimmed
    end
  end

  defp build_invoke_alias_argv(command, parsed)
       when is_binary(command) and is_map(parsed) do
    ["invoke", command]
    |> maybe_put_alias_json_option("--params", Map.get(parsed, :params, %{}))
    |> maybe_put_alias_json_option("--context", Map.get(parsed, :context, %{}))
    |> maybe_put_alias_string_option("--invocation-id", Map.get(parsed, :invocation_id))
    |> maybe_put_alias_string_option("--bus", Map.get(parsed, :bus))
  end

  defp maybe_put_alias_json_option(argv, _option, map)
       when is_list(argv) and is_map(map) and map_size(map) == 0,
       do: argv

  defp maybe_put_alias_json_option(argv, option, map)
       when is_list(argv) and is_binary(option) and is_map(map) do
    argv ++ [option, Jason.encode!(map)]
  end

  defp maybe_put_alias_string_option(argv, _option, nil) when is_list(argv), do: argv

  defp maybe_put_alias_string_option(argv, option, value)
       when is_list(argv) and is_binary(option) and is_binary(value) do
    argv ++ [option, value]
  end

  defp parse_top_level_command_name(command) when is_binary(command) do
    trimmed = String.trim(command)
    if trimmed == "", do: :error, else: {:ok, trimmed}
  end

  defp handle_parse_result({:ok, [:list], _result}, _parser, halt, runtime) do
    handle_list(halt, runtime)
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
    |> Enum.each(&IO.puts(:stderr, &1))

    halt.(1)
  end

  defp handle_parse_result({:error, subcommand_path, errors}, parser, halt, _runtime) do
    parser
    |> Optimus.Errors.format(subcommand_path, errors)
    |> Enum.each(&IO.puts(:stderr, &1))

    halt.(1)
  end

  defp handle_parse_result(:help, parser, halt, _runtime) do
    IO.puts(Optimus.help(parser))
    halt.(0)
  end

  defp handle_parse_result(:version, _parser, halt, _runtime) do
    IO.puts("command 0.1.0")
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
    bus = result.options.bus

    case safe_runtime_call("invoke", halt, fn ->
           invoke_runtime(runtime, command_name, params, context, invocation_id, bus)
         end) do
      {:ok, value} ->
        print_json_or_fail("invoke", value, halt)

      {:error, reason} ->
        IO.puts(:stderr, "invoke failed: #{inspect(reason)}")
        halt.(1)

      :halted ->
        :ok

      other ->
        invalid_runtime_response("invoke", other, halt)
    end
  end

  defp handle_list(halt, runtime) do
    case safe_runtime_call("list", halt, fn -> runtime.list_commands() end) do
      commands when is_list(commands) ->
        if valid_command_name_list?(commands) do
          Enum.each(commands, &IO.puts/1)
          :ok
        else
          invalid_runtime_response("list", commands, halt)
        end

      {:error, reason} ->
        IO.puts(:stderr, "list failed: #{inspect(reason)}")
        halt.(1)

      :halted ->
        :ok

      other ->
        invalid_runtime_response("list", other, halt)
    end
  end

  defp handle_dispatch(result, halt, runtime) do
    command_name = result.args.command
    params = result.options.params || %{}
    context = result.options.context || %{}
    invocation_id = result.options.invocation_id
    bus = result.options.bus

    case safe_runtime_call("dispatch", halt, fn ->
           dispatch_runtime(runtime, command_name, params, context, invocation_id, bus)
         end) do
      {:ok, invocation_id} when is_binary(invocation_id) ->
        print_json_or_fail("dispatch", %{"invocation_id" => invocation_id}, halt)

      {:ok, _invocation_id} = other ->
        invalid_runtime_response("dispatch", other, halt)

      {:error, reason} ->
        IO.puts(:stderr, "dispatch failed: #{inspect(reason)}")
        halt.(1)

      :halted ->
        :ok

      other ->
        invalid_runtime_response("dispatch", other, halt)
    end
  end

  defp handle_reload(halt, runtime) do
    case safe_runtime_call("reload", halt, fn -> runtime.reload() end) do
      :ok ->
        IO.puts(Jason.encode!(%{"status" => "ok"}))
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "reload failed: #{inspect(reason)}")
        halt.(1)

      :halted ->
        :ok

      other ->
        invalid_runtime_response("reload", other, halt)
    end
  end

  defp handle_register_command(result, halt, runtime) do
    command_path = result.args.command_path

    case safe_runtime_call("register-command", halt, fn ->
           runtime.register_command(command_path)
         end) do
      :ok ->
        IO.puts(Jason.encode!(%{"status" => "ok", "command_path" => command_path}))
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "register-command failed: #{inspect(reason)}")
        halt.(1)

      :halted ->
        :ok

      other ->
        invalid_runtime_response("register-command", other, halt)
    end
  end

  defp handle_unregister_command(result, halt, runtime) do
    command_name = result.args.command_name

    case safe_runtime_call("unregister-command", halt, fn ->
           runtime.unregister_command(command_name)
         end) do
      :ok ->
        IO.puts(Jason.encode!(%{"status" => "ok", "command_name" => command_name}))
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "unregister-command failed: #{inspect(reason)}")
        halt.(1)

      :halted ->
        :ok

      other ->
        invalid_runtime_response("unregister-command", other, halt)
    end
  end

  defp parser_spec do
    Optimus.new!(
      name: "command",
      description: "Signal-driven command runtime",
      version: "0.1.0",
      author: "Jido.Code.Command",
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
            ],
            bus: [
              value_name: "BUS",
              long: "--bus",
              help: "Optional bus target override",
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
            ],
            bus: [
              value_name: "BUS",
              long: "--bus",
              help: "Optional bus target override",
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

  defp invoke_runtime(runtime, command_name, params, context, invocation_id, bus) do
    runtime_opts =
      []
      |> maybe_put_runtime_opt(:invocation_id, invocation_id)
      |> maybe_put_runtime_opt(:bus, bus)

    case runtime_opts do
      [] ->
        runtime.invoke(command_name, params, context)

      opts ->
        if function_exported?(runtime, :invoke, 4) do
          runtime.invoke(command_name, params, context, opts)
        else
          legacy_context =
            context
            |> maybe_put_context_key(:invocation_id, invocation_id)
            |> maybe_put_context_key(:bus, bus)

          runtime.invoke(command_name, params, legacy_context)
        end
    end
  end

  defp dispatch_runtime(runtime, command_name, params, context, invocation_id, bus) do
    runtime_opts =
      []
      |> maybe_put_runtime_opt(:invocation_id, invocation_id)
      |> maybe_put_runtime_opt(:bus, bus)

    case runtime_opts do
      [] ->
        runtime.dispatch(command_name, params, context)

      opts ->
        if function_exported?(runtime, :dispatch, 4) do
          runtime.dispatch(command_name, params, context, opts)
        else
          legacy_context =
            context
            |> maybe_put_context_key(:invocation_id, invocation_id)
            |> maybe_put_context_key(:bus, bus)

          runtime.dispatch(command_name, params, legacy_context)
        end
    end
  end

  defp maybe_put_runtime_opt(opts, _key, nil) when is_list(opts), do: opts

  defp maybe_put_runtime_opt(opts, key, value) when is_list(opts) and is_atom(key),
    do: Keyword.put(opts, key, value)

  defp maybe_put_context_key(context, _key, nil) when is_map(context), do: context

  defp maybe_put_context_key(context, key, value) when is_map(context) and is_atom(key),
    do: Map.put(context, key, value)

  defp valid_command_name_list?(commands) when is_list(commands) do
    Enum.all?(commands, fn
      name when is_binary(name) -> String.trim(name) != ""
      _other -> false
    end)
  end

  defp print_json_or_fail(command, value, halt) when is_binary(command) do
    case Jason.encode(value, pretty: true) do
      {:ok, encoded} ->
        IO.puts(encoded)
        :ok

      {:error, reason} ->
        invalid_runtime_response(command, {:json_encode_failed, reason}, halt)
    end
  end

  defp invalid_runtime_response(command, response, halt) when is_binary(command) do
    formatted = inspect(response, charlists: :as_lists)
    IO.puts(:stderr, "#{command} failed: invalid runtime response: #{formatted}")
    halt.(1)
  end

  defp safe_runtime_call(command, halt, fun) when is_binary(command) and is_function(fun, 0) do
    fun.()
  rescue
    error ->
      IO.puts(:stderr, "#{command} failed: runtime exception: #{Exception.message(error)}")
      _ = halt.(1)
      :halted
  catch
    kind, reason ->
      formatted = inspect({kind, reason}, charlists: :as_lists)
      IO.puts(:stderr, "#{command} failed: runtime throw: #{formatted}")
      _ = halt.(1)
      :halted
  end
end
