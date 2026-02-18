defmodule Transport.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_add_deps: :app_tree,
        plt_add_apps: [:mix],
        plt_local_path: "dialyzer-plt",
        plt_core_path: "dialyzer-plt"
      ],
      listeners: [Phoenix.CodeReloader]
    ]
  end

  defp deps do
    [
      # locally, you can use :dialyxir in :dev mode, and we also add
      # :test to ensure CI can run it with a single compilation (in test target),
      # to reduce build time
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:saxy, "~> 1.5"},
      {:appsignal, "~> 2.0"},
      {:appsignal_phoenix, "~> 2.0"},
      {:ecto_erd, "~> 0.6.0", only: [:dev]}
    ]
  end

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate", "test"],
      "phx.migrate_phx.server": ["ecto.migrate", "phx.server"],
      check_all: [
        "format --check-formatted",
        ~s(npm "run linter:sass"),
        # from https://hexdocs.pm/mix/1.12/Mix.Task.html#run/2
        # Remember: by default, tasks will only run once, even when called repeatedly!
        # If you need to run a task multiple times, you need to re-enable it via reenable/1 or call it using rerun/2."
        # => here, npm task need to be run twice
        fn _ -> Mix.Task.reenable("npm") end,
        ~s(npm "run linter:ecma"),
        "credo --strict",
        "gettext.extract --check-up-to-date",
        "test"
      ]
    ]
  end

  def cli do
    [preferred_envs: [check_all: :test]]
  end

  defp aliases(:dev) do
    aliases() ++
      [
        "ecto.migrate": ["ecto.migrate", "ecto.dump"],
        run: [&set_worker_env/1, "run"]
      ]
  end

  defp aliases(_env) do
    aliases()
  end

  defp set_worker_env(_) do
    # Boot only in webserver mode when running `mix run`
    # See `config/runtime.exs`
    System.put_env("WORKER", "0")
  end
end
