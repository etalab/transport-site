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
      ]
    ]
  end

  defp deps do
    [
      {:dialyxir, "~> 1.1.0", only: :dev, runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      # To be removed once https://github.com/mochi/mochiweb/issues/233 is fixed
      # `override: true` is required because `html_sanitize_ex` also specifies this
      # dependency. The lack of hex.pm release led me to force this.
      {:mochiweb, github: "mochi/mochiweb", tag: "v2.21.0", override: true}
    ]
  end

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate", "test"],
      "phx.migrate_phx.server": ["ecto.migrate", "phx.server"]
    ]
  end
end
