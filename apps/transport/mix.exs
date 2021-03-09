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
        "vcr.show": :test
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
        :unidecode
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:csv, "~> 2.1"},
      {:earmark, "~> 1.3"},
      {:exconstructor, "~> 1.1"},
      {:gettext, "~> 0.11"},
      {:httpoison, "~> 1.5"},
      {:phoenix, "~> 1.5.7"},
      {:phoenix_html, "~> 2.13"},
      {:phoenix_markdown, "~> 1.0"},
      {:phoenix_live_view, "~> 0.15.0"},
      {:phoenix_html_sanitizer, "~> 1.1.0"},
      {:floki, ">= 0.0.0", only: :test},
      {:plug_cowboy, "~> 2.1"},
      {:recon, "~> 2.4"},
      {:vex, "~> 0.8"},
      {:quantum, "~> 2.3"},
      {:timex, "~> 3.5"},
      {:sentry, "~> 7.1"},
      {:scrivener, "~> 2.5"},
      # We'll use upstream again once https://github.com/mgwidmann/scrivener_html/pull/98 is merged
      {:scrivener_html, git: "https://github.com/thbar/scrivener_html.git", branch: "phoenix_1.5"},
      {:scrivener_list, "~>2.0"},
      {:jason, "~> 1.1"},
      {:open_api_spex, "~> 3.8"},
      {:gbfs, in_umbrella: true},
      {:datagouvfr, in_umbrella: true},
      {:helpers, in_umbrella: true},
      {:db, in_umbrella: true},
      {:castore, "~> 0.1.0"},
      {:mint, "~> 0.2.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:cors_plug, "~> 2.0"},
      {:exvcr, "~> 0.10", only: :test},
      {:hound, "~> 1.0", only: :test},
      {:credo, "~> 0.8", only: [:dev, :test], runtime: false},
      {:ex_aws, "~> 2.1"},
      {:ex_aws_s3, "~> 2.0"},
      {:unidecode, "~> 0.0.2"},
      {:ex_machina, "~> 2.4", only: :test}
    ]
  end
end
