# Writes a seeded, schema-conformant IRVE dynamic v3 CSV to stdout, matching the static file
# generated with the same options.
#
# mix run --no-start scripts/irve/v3/generate-dynamic.exs --seed 42 --stations 300 --networks 3 > irve-dynamique.csv

# The generators are test support, compiled only in the test env.
for file <- ~w(irve_v3_static_fixture_generator.ex irve_v3_dynamic_fixture_generator.ex),
    do: Code.require_file("test/support/#{file}", Mix.Project.apps_paths()[:transport])

alias Transport.IRVE.V3.{DynamicFixtureGenerator, StaticFixtureGenerator}

{opts, _args} = OptionParser.parse!(System.argv(), strict: [seed: :integer, stations: :integer, networks: :integer])

opts
|> StaticFixtureGenerator.generate()
|> DynamicFixtureGenerator.generate(Keyword.take(opts, [:seed]))
|> DynamicFixtureGenerator.to_csv()
|> IO.write()
