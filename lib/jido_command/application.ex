defmodule JidoCommand.Application do
  @moduledoc false

  use Application

  require Logger

  alias JidoCommand.Config.Loader
  alias JidoCommand.Config.Settings
  alias JidoCommand.Extensibility.CommandDispatcher
  alias JidoCommand.Extensibility.CommandRegistry

  @impl true
  def start(_type, _args) do
    settings =
      case Loader.load() do
        {:ok, loaded} ->
          loaded

        {:error, reason} ->
          Logger.warning("Failed to load settings.json, using defaults: #{inspect(reason)}")
          %Settings{}
      end

    children = [
      {Jido.Signal.Bus, Settings.bus_opts(settings)},
      {CommandRegistry,
       [
         bus: settings.bus_name,
         global_root: Loader.default_global_root(),
         local_root: Loader.default_local_root(),
         default_model: settings.commands_default_model
       ]},
      {CommandDispatcher,
       [
         bus: settings.bus_name,
         registry: CommandRegistry,
         max_concurrent: settings.commands_max_concurrent,
         permissions: Settings.permissions(settings)
       ]}
    ]

    opts = [strategy: :one_for_one, name: JidoCommand.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
