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
      {:oauth2, "~> 2.1"},
      {:hackney, "~> 1.18"},
      {:httpoison, ">= 0.0.0"},
      {:plug, ">= 0.0.0"},
      {:shared, in_umbrella: true},
      {:vex, "~> 0.9"},
      {:exvcr, "~> 0.13", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:sentry, "~> 11.0"},
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.10", only: :test}
    ]
  end
end
