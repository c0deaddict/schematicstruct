defmodule Schematicstruct.MixProject do
  use Mix.Project

  def project do
    [
      app: :schematicstruct,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:schematic, "0.5.2"},
      {:schematic, github: "c0deaddict/schematic", branch: "main", override: true}
    ]
  end
end
