defmodule Transport.Mixfile do
  use Mix.Project

  def project do
    [
      app: :transport,
      version: "0.0.1",
      elixir: "~> 1.8",
      elixirc_paths: elixirc_paths(Mix.env),
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      gettext: [{:write_reference_comments, false}],
      compilers: [:phoenix, :gettext] ++ Mix.compilers,
      preferred_cli_env: [
        vcr: :test, "vcr.delete": :test, "vcr.check": :test, "vcr.show": :test
      ],
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps(),
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Transport.Application, []},
      extra_applications: [
        :logger,
        :mime,
        :oauth2,
        :poolboy,
        :scrivener,
        :scrivener_html,
        :sentry,
        :unidecode,
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:csv, "~> 2.1"},
      {:earmark, "~> 1.3"},
      {:exconstructor, "~> 1.1"},
      {:gettext, "~> 0.11"},
      {:httpoison, "~> 1.5"},
      {:oauth2, "~> 0.9"},
      {:phoenix, "~> 1.4"},
      {:phoenix_html, "~> 2.13"},
      {:phoenix_markdown, "~> 1.0"},
      {:plug_cowboy, "~> 1.0"},
      {:poolboy, "~> 1.5"},
      {:recon, "~> 2.4"},
      {:vex, "~> 0.8"},
      {:quantum, "~> 2.3"},
      {:timex, "~> 3.5"},
      {:sentry, "~> 6.0"},
      {:scrivener, "~> 2.5"},
      {:scrivener_ecto, "~> 2.0"},
      {:scrivener_html, "~> 1.8"},
      {:scrivener_list, "~>2.0"},
      {:ecto, "~> 3.0"},
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"},
      {:jason, "~> 1.1"},
      {:geo_postgis, "~> 2.0"},
      {:open_api_spex, "~> 3.1"},
      {:gbfs, in_umbrella: true},

      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:exvcr, "~> 0.10", only: :test},
      {:hound, "~> 1.0", only: :test},
      {:credo, "~> 0.8", only: [:dev, :test], runtime: false},
      {:ex_aws, "~> 2.1"},
      {:ex_aws_s3, "~> 2.0"},
      {:unidecode, "~> 0.0.2"},
    ]
  end
end
