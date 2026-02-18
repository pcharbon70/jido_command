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
      {:jido, git: "https://github.com/agentjido/jido"},
      {:optimus, "0.6.1"},
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.12"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end
end
