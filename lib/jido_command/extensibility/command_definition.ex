defmodule JidoCommand.Extensibility.CommandDefinition do
  @moduledoc """
  Canonical representation of a markdown-defined command.
  """

  @type hook_enabled :: boolean()

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          command_module: module() | nil,
          model: String.t() | nil,
          allowed_tools: [String.t()],
          schema: keyword(),
          hooks: %{pre: hook_enabled(), after: hook_enabled()},
          body: String.t(),
          source_path: String.t()
        }

  defstruct name: nil,
            description: nil,
            command_module: nil,
            model: nil,
            allowed_tools: [],
            schema: [],
            hooks: %{pre: false, after: false},
            body: "",
            source_path: ""
end
