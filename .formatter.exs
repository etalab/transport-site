[
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "mix.exs",
    "config/*.exs",
    "apps/*/{lib,test}/**/*.{ex,exs,heex}",
    "scripts/**/*.exs",
    "ops_tests/**/*.exs"
  ],
  line_length: 120
]
