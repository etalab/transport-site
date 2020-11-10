defmodule Datagouvfr.MixProject do
  use Mix.Project

  def project do
    [
      app: :datagouvfr,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      gettext: [{:write_reference_comments, false}],
      compilers: [:gettext] ++ Mix.compilers,
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:gettext, ">= 0.0.0"},
      {:oauth2, "~> 0.9"},
      {:httpoison, ">= 0.0.0"},
      {:plug, ">= 0.0.0"},

      {:helpers, in_umbrella: true}
    ]
  end
end
