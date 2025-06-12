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
      {:phoenix, "~> 1.7.0"},
      {:phoenix_html, "~> 3.1"},
      {:sentry, "~> 10.1"},
      # required indirectly by sentry
      {:hackney, "~> 1.8"},
      {:jason, "~> 1.1"},
      {:nimble_csv, "~> 1.1"},
      {:finch, "~> 0.8"},
      {:ex_aws, "~> 2.1"},
      {:ex_aws_s3, "~> 2.0"},
      {:yaml_elixir, "~> 2.7"},
      {:cachex, "~> 3.5"},
      {:cors_plug, "~> 3.0"},
      {:saxy, "~> 1.5"},
      {:mox, "~> 1.1", only: :test},
      {:ymlr, "~> 5.0", only: :test},
      {:ecto, "~> 3.7", only: :test},
      # required for `TransportWeb.Plugs.AppSignalFilter`
      {:shared, in_umbrella: true},
      {:appsignal, "~> 2.0"},
      {:appsignal_phoenix, "~> 2.0"},
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      # Not something we want to encourage, but required to
      # properly test Finch-based code. Migrating to Req is
      # a better idea here ultimately
      {:bypass, "~> 2.1", only: :test}
    ]
  end
end
