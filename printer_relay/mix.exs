defmodule PrinterRelay.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/tmecklem/nerves_printer"

  def project do
    [
      app: :printer_relay,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Send ZPL from a Phoenix app to label printers connected over Phoenix Channels",
      package: package(),
      docs: [main: "readme", extras: ["README.md"], source_url: @source_url]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Server side: a Phoenix app hosting printers
      {:phoenix, "~> 1.7", optional: true},
      {:phoenix_pubsub, "~> 2.1", optional: true},
      # Client side: a device connecting a printer
      {:slipstream, "~> 1.2", optional: true},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      {:bandit, "~> 1.5", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md)
    ]
  end
end
