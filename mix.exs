defmodule Jido.Code.Command.MixProject do
  use Mix.Project
  @source_url "https://github.com/pcharbon70/jido_command"

  def project do
    [
      app: :jido_command,
      version: "0.1.0",
      description: description(),
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      package: package(),
      source_url: @source_url,
      deps: deps(),
      escript: escript()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Code.Command.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jido, "~> 2.0"},
      {:optimus, "0.6.1"},
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.12"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end

  defp escript do
    [
      main_module: Jido.Code.Command.Escript,
      name: "command",
      app: nil,
      include_priv_for: [:tzdata]
    ]
  end

  defp description do
    "Command-only runtime built on Jido actions and signal bus primitives."
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url
      },
      files: [
        "lib",
        "docs",
        ".formatter.exs",
        "mix.exs",
        "README.md",
        "LICENSE"
      ]
    ]
  end
end
