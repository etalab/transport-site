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
        # NOTE: normally app_tree to get transitive dependencies,
        # but our CircleCI setup is exploding due, so I tried to reduce time a bit.
        plt_add_deps: :app_direct,
        plt_add_apps: [:mix],
        plt_local_path: "dialyzer-plt",
        plt_core_path: "dialyzer-plt"
      ]
    ]
  end

  defp deps do
    [
      # NOTE: using master to be able to use `plt_local_path` option
      {:dialyxir, "~> 1.0.0", only: :dev, runtime: false, git: "https://github.com/jeremyjh/dialyxir.git"},
      {:excoveralls, "~> 0.10", only: :test}
    ]
  end

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate", "test"],
      "phx.migrate_phx.server": ["ecto.migrate", "phx.server"]
    ]
  end
end
