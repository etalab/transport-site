# Integration tests setup.
Application.ensure_all_started(:hound)

# Exclude all external tests from running (unless RUN_ALL is provided)
run_all = System.get_env("RUN_ALL") == "1"
excludes = if run_all, do: [], else: [:integration, :solution, :external]
ExUnit.configure(exclude: excludes ++ [:pending])

# Start ExUnit.
ExUnit.start()

# Define VCR's path.
ExVCR.Config.cassette_library_dir("test/fixture/cassettes")

Ecto.Adapters.SQL.Sandbox.mode(DB.Repo, :manual)
