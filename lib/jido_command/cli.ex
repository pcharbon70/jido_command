defmodule JidoCommand.CLI do
  @moduledoc """
  Optimus-based CLI for invoking and listing registered commands.
  """

  @spec main([String.t()], (integer() -> no_return())) :: :ok | no_return()
  def main(argv, halt \\ &System.halt/1) do
    parser = parser_spec()
    result = Optimus.parse(parser, argv)
    handle_parse_result(result, parser, halt)
  end

  defp handle_parse_result({:ok, [:list], _result}, _parser, _halt) do
    JidoCommand.list_commands()
    |> Enum.each(&IO.puts/1)

    :ok
  end

  defp handle_parse_result({:ok, [:invoke], result}, _parser, halt) do
    handle_invoke(result, halt)
  end

  defp handle_parse_result({:error, errors}, parser, halt) do
    parser
    |> Optimus.Errors.format(errors)
    |> Enum.each(&IO.puts/1)

    halt.(1)
  end

  defp handle_parse_result({:error, subcommand_path, errors}, parser, halt) do
    parser
    |> Optimus.Errors.format(subcommand_path, errors)
    |> Enum.each(&IO.puts/1)

    halt.(1)
  end

  defp handle_parse_result(:help, parser, halt) do
    IO.puts(Optimus.help(parser))
    halt.(0)
  end

  defp handle_parse_result(:version, _parser, halt) do
    IO.puts("jido_command 0.1.0")
    halt.(0)
  end

  defp handle_parse_result({:help, subcommand_path}, parser, halt) do
    IO.puts(parser |> Optimus.Help.help(subcommand_path, 100) |> Enum.join("\n"))
    halt.(0)
  end

  defp handle_parse_result({:ok, _result}, parser, halt) do
    IO.puts(Optimus.help(parser))
    halt.(1)
  end

  defp handle_invoke(result, halt) do
    command_name = result.args.command
    params = result.options.params || %{}
    context = result.options.context || %{}

    case JidoCommand.invoke(command_name, params, context) do
      {:ok, value} ->
        IO.puts(Jason.encode!(value, pretty: true))
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "invoke failed: #{inspect(reason)}")
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
end
