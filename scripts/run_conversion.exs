url = "https://opendata.lillemetropole.fr/api/datasets/1.0/transport_arret_transpole-point/alternative_exports/gtfs_zip"
# create a filesystem compatible name. also, avoid https://github.com/rust-transit/gtfs-to-geojson/issues/5 by prefixing with something
file = "download-" <> Regex.replace(~r/\W/, url, "-")

unless File.exists?(file) do
  %{body: body, status_code: 200} = HTTPoison.get!(url)
  IO.puts "Writing file #{file}..."
  File.write!(file, body)
end

conversion = file <> ".geojson"

program = "../gtfs-to-geojson/target/release/gtfs-geojson"
# required or you will get :noent error
program = Path.expand(program)

IO.puts "Running conversion..."
output_file = file <> ".geojson"

unit = :millisecond
start_time = System.monotonic_time(unit)
{_stdout, 0} = MuonTrap.cmd(program, ["--input", file, "--output", output_file])
time_taken = System.monotonic_time(unit) - start_time

IO.puts "Done with conversion (time taken: #{time_taken/1000.0} sec)"
