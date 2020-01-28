defmodule Transport.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_deps: :transitive, ignore_warnings: ".dialyzer_ignore.exs"]
    ]
  end

  defp deps do
    [{:dialyxir, "~> 1.0.0-rc.7", only: [:dev], runtime: false}]
  end

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate", "test"],
      "phx.migrate_phx.server": ["ecto.migrate", "phx.server"]
    ]
  end
end
