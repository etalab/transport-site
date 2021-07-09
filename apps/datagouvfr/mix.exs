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
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
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
      # Using master until https://github.com/CargoSense/vex/issues/68 is fixed
      {:vex, github: "CargoSense/vex", ref: "328a39f7"},
      {:exvcr, "~> 0.10", only: :test},
      {:mox, "~> 1.0.0", only: :test}
    ]
  end
end
