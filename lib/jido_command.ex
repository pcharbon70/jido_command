defmodule JidoCommand do
  @moduledoc """
  Public API for invoking and dispatching markdown-defined Jido commands.
  """

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias JidoCommand.Extensibility.ExtensionRegistry

  @spec list_commands(keyword()) :: [String.t()]
  def list_commands(opts \\ []) do
    registry = Keyword.get(opts, :registry, ExtensionRegistry)
    ExtensionRegistry.list_commands(registry)
  end

  @spec invoke(String.t(), map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def invoke(name, params \\ %{}, context \\ %{}, opts \\ []) when is_binary(name) do
    registry = Keyword.get(opts, :registry, ExtensionRegistry)
    bus = Keyword.get(opts, :bus, :jido_code_bus)
    invocation_id = Keyword.get(opts, :invocation_id, default_invocation_id())

    with {:ok, module} <- ExtensionRegistry.get_command(name, registry) do
      run_context =
        context
        |> Map.put_new(:bus, bus)
        |> Map.put_new(:invocation_id, invocation_id)

      Jido.Exec.run(module, params, run_context)
    end
  end

  @spec dispatch(String.t(), map(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def dispatch(name, params \\ %{}, context \\ %{}, opts \\ []) when is_binary(name) do
    bus = Keyword.get(opts, :bus, :jido_code_bus)
    invocation_id = Keyword.get(opts, :invocation_id, default_invocation_id())

    payload = %{
      "name" => name,
      "params" => params,
      "context" => context,
      "invocation_id" => invocation_id
    }

    with {:ok, signal} <- Signal.new("command.invoke", payload, source: "/jido_command"),
         {:ok, _recorded} <- Bus.publish(bus, [signal]) do
      {:ok, invocation_id}
    end
  end

  defp default_invocation_id do
    Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end
end
