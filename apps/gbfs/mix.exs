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
      {:httpoison, "~> 1.5.0"},
      {:exshape, "~> 2.2.6"},
      {:phoenix, "~> 1.4"},
      {:iconv, "~> 1.0.10"},
      {:sweet_xml, ">= 0.0.0"},
      {:jason, ">= 0.0.0"},
      {:cors_plug, "~> 2.0"},
      {:sentry, "~> 7.1"},
      {:exvcr, "~> 0.10", only: :test},
      {:mock, "~> 0.3.6", only: :test}
    ]
  end
end
