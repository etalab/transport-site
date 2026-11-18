# Writes a seeded, schema-conformant IRVE tarifs v3 CSV to stdout: the tariffs referenced by the static file
# generated with the same options.
# `--now` (optional, a date) is the reference for all generated dates; the default keeps output stable over time.
#
# mix run --no-start scripts/irve/v3/generate-tarifs.exs --seed 42 --stations 300 --networks 3 --now 2026-11-18 > irve-tarifs.csv

# The generators are test support, compiled only in the test env.
for file <- ~w(irve_v3_static_fixture_generator.ex irve_v3_tarifs_fixture_generator.ex),
    do: Code.require_file("test/support/#{file}", Mix.Project.apps_paths()[:transport])

alias Transport.IRVE.V3.{StaticFixtureGenerator, TarifsFixtureGenerator}

{opts, _args} =
  OptionParser.parse!(System.argv(), strict: [seed: :integer, stations: :integer, networks: :integer, now: :string])

opts = Keyword.replace_lazy(opts, :now, &DateTime.new!(Date.from_iso8601!(&1), ~T[00:00:00]))

opts
|> StaticFixtureGenerator.generate()
|> TarifsFixtureGenerator.generate(Keyword.take(opts, [:seed, :now]))
|> TarifsFixtureGenerator.to_csv()
|> IO.write()
