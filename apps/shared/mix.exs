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
      test_coverage: [tool: ExCoveralls]
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
      {:timex, ">= 0.0.0"},
      {:httpoison, ">= 0.0.0"},
      # Mint is used by our HttpStream shared component, so we add an explicity dependency
      {:mint, "~> 0.2.0"},
      # Required for ConditionalJSONEncoder shared component
      {:phoenix, "~> 1.5.7"},
      # The global app config references Sentry.LoggerBackend. We add it in "shared"
      # as an implicit dependency, to ensure `Sentry.LoggerBackend` is always defined,
      # otherwise running tests for an individual umbrella sub-app will raise error.
      {:sentry, "~> 8.0.0"},
      # Similarly, Jason is configured as `json_library` by the main app, so it will
      # be required no matter what.
      {:jason, ">= 0.0.0"}
    ]
  end
end
