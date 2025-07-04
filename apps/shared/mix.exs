defmodule Shared.MixProject do
  use Mix.Project

  def project do
    [
      app: :shared,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
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
      mod: {Shared.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:timex, ">= 0.0.0"},
      {:httpoison, ">= 0.0.0"},
      {:req, "~> 0.5"},
      {:bypass, "~> 2.1", only: :test},
      {:mox, "~> 1.1", only: :test},
      # Mint is used by our HttpStream shared component, so we add an explicity dependency
      {:mint, "~> 1.2"},
      # Finch is used for built-in streaming
      {:finch, "~> 0.8"},
      # Required for the ConditionalJSONEncoder shared component, but
      # there is probably a way to avoid that?
      {:phoenix, "~> 1.7.0"},
      # The global app config references Sentry.LoggerBackend. We add it in "shared"
      # as an implicit dependency, to ensure `Sentry.LoggerBackend` is always defined,
      # otherwise running tests for an individual umbrella sub-app will raise error.
      # A better way to achieve this will be to configure it at runtime, like described
      # in https://github.com/getsentry/sentry-elixir/pull/472.
      {:sentry, "~> 10.1"},
      # Similarly, Jason is configured as `json_library` by the main app, so it will
      # be required no matter what.
      {:jason, ">= 0.0.0"},
      {:ex_cldr_numbers, "~> 2.0"},
      {:ex_cldr_calendars, "~> 1.26"},
      {:ex_cldr_lists, "~> 2.11"},
      {:ex_cldr_units, "~> 3.17"},
      {:ex_aws, "~> 2.1"},
      {:ex_aws_s3, "~> 2.0"},
      {:cachex, "~> 3.5"},
      {:ex_json_schema, "~> 0.10"},
      # added because of `TransportWeb.Plugs.AppSignalFilter`
      {:appsignal, "~> 2.0"},
      {:appsignal_phoenix, "~> 2.0"},
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.10", only: :test}
    ]
  end
end
