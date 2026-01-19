exclude = [:pending]
# NOTE: the CI variable is defined by CircleCI (and oftent by CI providers) here:
# https://circleci.com/docs/2.0/env-vars/#built-in-environment-variables
extra_exclude =
  if System.get_env("CI") == "true" do
    # Run tests tagged with `:ci_only_on_mondays` only:
    # - within the continuous integration env
    # - on Mondays
    case Date.utc_today() |> Date.day_of_week() do
      1 -> []
      _ -> [:ci_only_on_mondays]
    end
  else
    [:transport_tools, :ci_only_on_mondays, :external, :timescaledb]
  end

ExUnit.configure(exclude: exclude ++ extra_exclude)

{:ok, _} = Application.ensure_all_started(:ex_machina)

# Start ExUnit.
ExUnit.start()

# Define VCR's path.
ExVCR.Config.cassette_library_dir("test/fixture/cassettes")

# Disable triggers on dataset, causing deadlocks
DB.Repo.query!("ALTER TABLE dataset DISABLE TRIGGER refresh_dataset_geographic_view_trigger")
DB.Repo.query!("ALTER TABLE dataset DISABLE TRIGGER dataset_update_trigger")

Ecto.Adapters.SQL.Sandbox.mode(DB.Repo, :manual)
