defmodule Transport.Mixfile do
  use Mix.Project

  def project do
    [
      app: :transport,
      version: "0.0.1",
      elixir: "~> 1.6.1",
      elixirc_paths: elixirc_paths(Mix.env),
      gettext: [{:write_reference_comments, false}],
      compilers: [:phoenix, :gettext] ++ Mix.compilers,
      preferred_cli_env: [
        vcr: :test, "vcr.delete": :test, "vcr.check": :test, "vcr.show": :test
      ],
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Transport.Application, []},
      extra_applications: [
        :faker,
        :logger,
        :mime,
        :oauth2,
        :poolboy,
        :scrivener,
        :scrivener_html
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
      {:csv, "~> 2.0.0"},
      {:earmark, "~> 1.2"},
      {:exconstructor, "~> 1.1"},
      {:faker, "~> 0.10"},
      {:gettext, "~> 0.11"},
      {:httpoison, "~> 1.0"},
      {:oauth2, "~> 0.9"},
      {:phoenix, "~> 1.3"},
      {:phoenix_html, "~> 2.10"},
      {:phoenix_markdown, "~> 1.0"},
      {:plug_cowboy, "~> 1.0"},
      {:poolboy, "~> 1.5"},
      {:recon, "~> 2.3"},
      {:uuid, "~> 1.1"},
      {:vex, "~> 0.6"},
      {:quantum, "~> 2.3"},
      {:timex, "~> 3.0"},
      {:scrivener, "~> 2.0"},
      {:scrivener_ecto, "~> 2.0"},
      {:scrivener_html, "~> 1.7"},
      {:phoenix_live_reload, "~> 1.0", only: :dev},
      {:exvcr, "~> 0.10.3", only: :test},
      {:hound, "~> 1.0", only: :test},
      {:credo, "~> 0.8", only: [:dev, :test], runtime: false},
      {:ex_guard, "~> 1.3", only: :dev},
      {:ecto, "~> 3.0"},
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"},
      {:jason, "~> 1.1"},
      {:geo_postgis, "~> 2.0"}
    ]
  end

  defp aliases do
    [
     "test": ["ecto.create --quiet", "ecto.migrate", "test"],
     "phx.migrate_phx.server": ["ecto.migrate", "phx.server"]
    ]
  end
end
