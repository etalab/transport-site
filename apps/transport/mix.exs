defmodule Transport.Mixfile do
  use Mix.Project

  def project do
    [
      app: :transport,
      version: "0.0.1",
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      gettext: [{:write_reference_comments, false}],
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      preferred_cli_env: [
        vcr: :test,
        "vcr.delete": :test,
        "vcr.check": :test,
        "vcr.show": :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      mod: {Transport.Application, []},
      extra_applications: [
        :logger,
        :mime,
        :unidecode,
        :phoenix_ecto
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:csv, "~> 2.1"},
      {:earmark, "~> 1.4"},
      {:gettext, "~> 0.11"},
      {:httpoison, "~> 1.8.0"},
      {:phoenix, "~> 1.5.7"},
      {:phoenix_html, "~> 2.13"},
      {:phoenix_markdown, "~> 1.0"},
      {:phoenix_live_view, "~> 0.15.0"},
      {:html_sanitize_ex, "~> 1.4"},
      {:floki, ">= 0.0.0", only: :test},
      {:plug_cowboy, "~> 2.3"},
      {:recon, "~> 2.4"},
      {:quantum, "~> 3.4"},
      {:timex, "~> 3.5"},
      {:sentry, "~> 8.0"},
      {:scrivener, "~> 2.5"},
      # We'll use upstream again once https://github.com/mgwidmann/scrivener_html/pull/98 is merged
      {:scrivener_html, git: "https://github.com/thbar/scrivener_html.git", branch: "phoenix_1.5"},
      {:scrivener_list, "~>2.0"},
      {:jason, "~> 1.1"},
      {:open_api_spex, "~> 3.8"},
      {:gbfs, in_umbrella: true},
      {:datagouvfr, in_umbrella: true},
      {:shared, in_umbrella: true},
      {:db, in_umbrella: true},
      {:unlock, in_umbrella: true},
      {:castore, "~> 0.1.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:cors_plug, "~> 2.0"},
      {:exvcr, "~> 0.10", only: :test},
      {:credo, "~> 1.5.0", only: [:dev, :test], runtime: false},
      # NOTE: we cannot upgrade to the very latest (2.2.x) because of
      # https://github.com/parroty/exvcr/issues/153#issuecomment-874864317
      {:ex_aws, "~> 2.1"},
      {:ex_aws_s3, "~> 2.0"},
      {:unidecode, "~> 1.0.0"},
      {:phoenix_ecto, "~> 4.0"},
      {:sizeable, "~> 1.0"},
      {:mox, "~> 1.0.0", only: :test},
      {:rambo, "~> 0.3"}
    ]
  end
end
