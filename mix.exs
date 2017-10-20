defmodule Transport.Mixfile do
  use Mix.Project

  def project do
    [
      app: :transport,
      version: "0.0.1",
      elixir: "~> 1.5",
      elixirc_paths: elixirc_paths(Mix.env),
      compilers: [:phoenix, :gettext] ++ Mix.compilers,
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Transport.Application, []},
      extra_applications: [:logger, :runtime_tools, :oauth2]
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
      {:cowboy, "~> 1.0"},
      {:earmark, "~> 1.2"},
      {:gettext, "~> 0.11"},
      {:oauth2, "~> 0.9"},
      {:phoenix, "~> 1.3"},
      {:phoenix_html, "~> 2.10"},
      {:phoenix_pubsub, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.0", only: :dev},
      {:exvcr, "~> 0.8", only: :test},
      {:eye_drops, "~> 1.3", only: :dev},
      {:hound, "~> 1.0.2", only: :test},
      {:credo, "~> 0.8", only: [:dev, :test], runtime: false}
    ]
  end
end
