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
      extra_applications: [:logger, :oauth2, :amqp, :mongodb, :poolboy, :mime]
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
      {:amqp, "~> 0.3.0"},
      {:cowboy, "~> 1.0"},
      {:earmark, "~> 1.2"},
      {:gettext, "~> 0.11"},
      {:httpoison, "~> 0.13"},
      {:ja_serializer, "~> 0.12.0"},
      {:mime, "~> 1.1.0"},
      {:mongodb, ">= 0.0.0"},
      {:oauth2, "~> 0.9"},
      {:phoenix, "~> 1.3"},
      {:phoenix_html, "~> 2.10"},
      {:phoenix_pubsub, "~> 1.0"},
      {:poolboy, ">= 0.0.0"},
      {:uuid, "~> 1.1"},
      {:vex, "~> 0.6"},
      {:eye_drops, "~> 1.3", only: :dev},
      {:phoenix_live_reload, "~> 1.0", only: :dev},
      {:exvcr, "~> 0.8", only: :test},
      {:hound, "~> 1.0.2", only: :test},
      {:credo, "~> 0.8", only: [:dev, :test], runtime: false}
    ]
  end
end
