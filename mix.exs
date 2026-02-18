defmodule JidoCommand.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_command,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {JidoCommand.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jido, git: "https://github.com/agentjido/jido"}
    ]
  end
end
