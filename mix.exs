defmodule Transport.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
    ]
  end

  defp deps do
    []
  end

  defp aliases do
    [
     test: ["ecto.create --quiet", "ecto.migrate", "test"],
     "phx.migrate_phx.server": ["ecto.migrate", "phx.server"]
    ]
  end
end
