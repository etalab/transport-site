defmodule Transport.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_add_deps: :app_tree,
        plt_add_apps: [:mix],
        plt_local_path: "dialyzer-plt",
        plt_core_path: "dialyzer-plt"
      ],
      preferred_cli_env: [
        check_all: :test
      ]
    ]
  end

  defp deps do
    [
      # locally, you can use :dialyxir in :dev mode, and we also add
      # :test to ensure CI can run it with a single compilation (in test target),
      # to reduce build time
      {:dialyxir, "~> 1.1.0", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.10", only: :test}
    ]
  end

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate", "test"],
      "phx.migrate_phx.server": ["ecto.migrate", "phx.server"],
      check_all: [
        "format --check-formatted",
        "npm \"run linter:sass\"",
        fn _ -> Mix.Task.reenable("npm") end,
        "npm \"run linter:ecma\"",
        "credo --strict",
        "gettext.extract --check-up-to-date",
        "test"
      ]
    ]
  end
end
