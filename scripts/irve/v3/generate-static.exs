# Writes a seeded, schema-conformant IRVE static v3 CSV to stdout.
#
# mix run --no-start scripts/irve/v3/generate-static.exs --seed 42 --stations 300 --networks 3 > irve.csv

alias Transport.IRVE.V3.StaticFixtureGenerator

{opts, _args} = OptionParser.parse!(System.argv(), strict: [seed: :integer, stations: :integer, networks: :integer])

opts
|> StaticFixtureGenerator.generate()
|> StaticFixtureGenerator.to_csv()
|> IO.write()
