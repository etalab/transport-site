exclude = [:pending]
extra_exclude = if System.get_env("CI") == "1", do: [], else: [:transport_tools]

ExUnit.configure(exclude: exclude ++ extra_exclude)

{:ok, _} = Application.ensure_all_started(:ex_machina)

# Start ExUnit.
ExUnit.start()

# Define VCR's path.
ExVCR.Config.cassette_library_dir("test/fixture/cassettes")

Ecto.Adapters.SQL.Sandbox.mode(DB.Repo, :manual)
