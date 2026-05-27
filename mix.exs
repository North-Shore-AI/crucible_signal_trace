defmodule CrucibleSignalTrace.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/North-Shore-AI/crucible_signal_trace"

  def project do
    [
      app: :crucible_signal_trace,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "CrucibleSignalTrace",
      description:
        "Bounded forward-pass trace schema for Crucible signal captures and decode telemetry",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        ci: :test,
        docs: :dev
      ]
    ]
  end

  defp deps do
    [
      {:crucible_signal, path: "../crucible_signal"},
      {:crucible_tap, path: "../crucible_tap"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.40.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      ci: [
        "deps.get",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "docs"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      source_ref: "main",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  defp package do
    [
      name: "crucible_signal_trace",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib assets mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end
end
