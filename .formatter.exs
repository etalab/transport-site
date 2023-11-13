[
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "mix.exs",
    "config/*.exs",
    "apps/*/{lib,test}/**/*.{ex,exs,heex}",
    "apps/transport/priv/repo/migrations/*.{ex,exs}",
    "scripts/**/*.exs",
    "ops_tests/**/*.exs"
  ],
  line_length: 120
]
