defmodule Unlock.MixProject do
  use Mix.Project

  def project do
    [
      app: :unlock,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      mod: {Unlock.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.6.2"},
      {:phoenix_html, "~> 3.1"},
      {:sentry, "~> 8.0"},
      # required indirectly by sentry
      {:hackney, "~> 1.8"},
      {:jason, "~> 1.1"},
      {:finch, "~> 0.8"},
      {:yaml_elixir, "~> 2.7"},
      {:cachex, "~> 3.4"},
      {:mox, "~> 1.0.0", only: :test},
      {:ymlr, "~> 2.0", only: :test}
    ]
  end
end
