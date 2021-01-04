defmodule Db.MixProject do
  use Mix.Project

  def project do
    [
      app: :db,
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
      extra_applications: [:logger],
      mod: {Db.Application, []}
    ]
  end

  defp deps do
    [
      {:ecto, "~> 3.1"},
      {:ecto_sql, "~> 3.1"},
      {:postgrex, ">= 0.0.0"},
      {:geo_postgis, "~> 2.0"},
      {:scrivener, "~> 2.5"},
      {:scrivener_ecto, "~> 2.0"},
      {:gettext, "~> 0.11"},
      {:httpoison, ">= 0.0.0"},
      {:phoenix_html, ">= 0.0.0"},
      {:jason, ">= 0.0.0"},
      {:datagouvfr, in_umbrella: true},
      {:helpers, in_umbrella: true},
      {:ex_aws, ">= 0.0.0"},
      {:ex_aws_s3, ">= 0.0.0"},
      {:sentry, ">= 0.0.0"},
      {:typed_ecto_schema, ">= 0.1.1"},
      {:vex, "~> 0.8"}
    ]
  end
end
