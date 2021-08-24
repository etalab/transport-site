ExUnit.configure(exclude: [:pending])

{:ok, _} = Application.ensure_all_started(:ex_machina)

# Start ExUnit.
ExUnit.start()

# Define VCR's path.
ExVCR.Config.cassette_library_dir("test/fixture/cassettes")

Ecto.Adapters.SQL.Sandbox.mode(DB.Repo, :manual)

# Temporary solution to consider warnings as errors during tests,
# until `mix test --warning-as--errors` is available (Elixir 1.12+)
# https://github.com/elixir-lang/elixir/issues/3223#issuecomment-751876927
Code.put_compiler_option(:warnings_as_errors, true)
