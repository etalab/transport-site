# Delete (unused) legacy buckets `dataset-<datagouv_id>/` (prod) and
# `testdataset-<datagouv_id>/` (staging) using `mc`.
# See https://github.com/transportdatagouvfr/deploy/issues/31#issuecomment-926381226
#
# Usage:    elixir scripts/delete_legacy_dataset_buckets.exs <mc-alias> | tee audit.log

[mc_alias] = System.argv()

{out, 0} = System.cmd("mc", ["ls", "#{mc_alias}/"])

buckets =
  ~r/(?:test)?dataset-[0-9a-f]{24}/
  |> Regex.scan(out)
  |> Enum.map(&hd/1)
  |> Enum.uniq()
  |> Enum.sort()

IO.puts("#{length(buckets)} bucket(s) sur '#{mc_alias}'.")
Enum.each(buckets, &IO.puts("  " <> &1))
"yes" = IO.gets("\nType 'yes' to delete: ") |> String.trim()

for b <- buckets do
  {_, code} = System.cmd("mc", ["rb", "--force", "#{mc_alias}/#{b}"], stderr_to_stdout: true)
  IO.puts("#{DateTime.utc_now()}\t#{b}\t#{if(code == 0, do: "OK", else: "FAIL")}")
end
