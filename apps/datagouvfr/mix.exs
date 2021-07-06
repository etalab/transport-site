defmodule Datagouvfr.MixProject do
  use Mix.Project

  def project do
    [
      app: :datagouvfr,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.8",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      gettext: [{:write_reference_comments, false}],
      compilers: [:gettext] ++ Mix.compilers(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:gettext, ">= 0.0.0"},
      {:oauth2, "~> 0.9"},
      {:httpoison, ">= 0.0.0"},
      {:plug, ">= 0.0.0"},
      {:shared, in_umbrella: true},
      {:vex, "~> 0.8"},
      {:exvcr, "~> 0.10", only: :test},
      {:mox, "~> 1.0.0", only: :test}
    ]
  end
end
