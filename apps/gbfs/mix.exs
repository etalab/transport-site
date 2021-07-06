defmodule GBFS.MixProject do
  use Mix.Project

  def project do
    [
      app: :gbfs,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.8",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      mod: {GBFS.Application, []},
      extra_applications: [:logger, :runtime_tools, :iconv]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:cachex, "~> 3.3"},
      {:httpoison, "~> 1.8.0"},
      {:phoenix, "~> 1.5.7"},
      {:iconv, "~> 1.0.10"},
      {:sweet_xml, ">= 0.0.0"},
      {:jason, ">= 0.0.0"},
      {:cors_plug, "~> 2.0"},
      {:sentry, "~> 8.0"},
      # Required for ConditionalJSONEncoder which is referenced by global config,
      # otherwise the tests won't run. Not sure if there's a better way for this,
      # since the GBFS app itself does not currently rely on conditional encoding.
      {:shared, in_umbrella: true},
      {:exvcr, "~> 0.10", only: :test},
      {:mock, "~> 0.3.6", only: :test},
      {:bypass, "~> 2.1", only: :test}
    ]
  end
end
