defmodule JidoCommand.Extensibility.CommandDefinition do
  @moduledoc """
  Canonical representation of a markdown-defined command.
  """

  @type hook_path :: String.t() | nil

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          command_module: module() | nil,
          model: String.t() | nil,
          allowed_tools: [String.t()],
          schema: keyword(),
          hooks: %{pre: hook_path(), after: hook_path()},
          body: String.t(),
          source_path: String.t()
        }

  defstruct name: nil,
            description: nil,
            command_module: nil,
            model: nil,
            allowed_tools: [],
            schema: [],
            hooks: %{pre: nil, after: nil},
            body: "",
            source_path: ""
end
