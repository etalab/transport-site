defmodule Transport.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      start_permanent: Mix.env() == :prod,
      hex: [
        cooldown: "7d",
        # Advisories acknowledged because no drop-in fix is available yet:
        #  - hackney: fixed only in 4.x (major release adding HTTP/2/3), needs a dedicated upgrade PR
        #    (hackney is used directly and as httpoison/tesla adapter).
        #    https://github.com/benoitc/hackney/security/advisories/GHSA-pj7v-xfvx-wmjq
        #  - earmark: unmaintained/retired, the stored-XSS won't be fixed upstream — migrate to MDEx.
        #    Untrusted markdown is already sanitized via HtmlSanitizeEx, so the real risk is low.
        #  - decimal: DoS fixed only in decimal 3.x, blocked by deps still pinning ~> 2.0 (ecto etc.).
        #    Revisit once the ecosystem allows decimal 3.x; check for untrusted decimal parsing meanwhile.
        #  - cowlib: 2 CRLF-injection advisories, no released fix (2.18.0 is latest under cowboy 2.17),
        #    but a patch is in progress upstream. Only exploitable if untrusted data reaches response
        #    headers/cookies, which app code doesn't do. Tracking:
        #    https://github.com/ninenines/cowlib/issues/152 (EEF-CVE-2026-43969, cookie injection)
        #    https://osv.dev/vulnerability/EEF-CVE-2026-43966 (response splitting)
        ignore_advisories: [
          # hackney (upgrade to 4.x)
          "EEF-CVE-2026-47069",
          "EEF-CVE-2026-47071",
          "EEF-CVE-2026-47075",
          "EEF-CVE-2026-47076",
          # earmark stored XSS (migrate to MDEx)
          "EEF-CVE-2026-48591",
          # decimal DoS (fix needs 3.x, blocked by ecosystem)
          "EEF-CVE-2026-32686",
          # cowlib injection (no fix published yet)
          "EEF-CVE-2026-43966",
          "EEF-CVE-2026-43969"
        ],
        # earmark is retired (unmaintained); acknowledged until the MDEx migration above.
        ignore_retirements: [:earmark]
      ],
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
