# Validates IRVE v3 files (any of the 3) and prints the file-level errors and error counts per code.
# `--out` (optional, a directory) receives the full report: `manifest.json` and one Parquet file per input.
# Exits with 1 if any file is invalid.
#
# mix run --no-start scripts/irve/v3/validate.exs --statique irve.csv --dynamique dyn.csv --tarifs tarifs.csv --out report

alias Transport.IRVE.V3.{Report, Validator}

{opts, _args} =
  OptionParser.parse!(System.argv(), strict: [statique: :string, dynamique: :string, tarifs: :string, out: :string])

{out, paths} = Keyword.pop(opts, :out)
report = paths |> Map.new(fn {role, path} -> {role, File.read!(path)} end) |> Validator.validate()
if out, do: Report.write!(report, out)

for {role, file} <- Report.manifest(report).files do
  IO.puts("#{role} (#{file.schema}, #{file.n_rows || "?"} rows, sha256 #{file.sha256})")
  for error <- file.file_errors, do: IO.puts("  file error: #{inspect(error)}")

  for {code, %{errors: errors}} <- Enum.sort(file.counts), errors > 0, do: IO.puts("  #{code}: #{errors} error(s)")
end

if Report.valid?(report), do: IO.puts("valid"), else: System.halt(1)
