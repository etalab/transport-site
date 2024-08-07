exclude = [:pending]
# NOTE: the CI variable is defined by CircleCI (and oftent by CI providers) here:
# https://circleci.com/docs/2.0/env-vars/#built-in-environment-variables
extra_exclude =
  if System.get_env("CI") == "true" do
    # Run :documentation_links only on Mondays
    case Date.utc_today() |> Date.day_of_week() do
      1 -> []
      _ -> [:documentation_links]
    end
  else
    [:transport_tools, :documentation_links, :external]
  end

ExUnit.configure(exclude: exclude ++ extra_exclude)

{:ok, _} = Application.ensure_all_started(:ex_machina)

# Start ExUnit.
ExUnit.start()

# Define VCR's path.
ExVCR.Config.cassette_library_dir("test/fixture/cassettes")

Ecto.Adapters.SQL.Sandbox.mode(DB.Repo, :manual)
