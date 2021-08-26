ExUnit.configure(exclude: [:pending])

{:ok, _} = Application.ensure_all_started(:ex_machina)

# Start ExUnit.
ExUnit.start()

# Define VCR's path.
ExVCR.Config.cassette_library_dir("test/fixture/cassettes")

Ecto.Adapters.SQL.Sandbox.mode(DB.Repo, :manual)
