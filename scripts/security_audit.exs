# Scan mix.lock against hex.pm security advisories. Exit 1 on any match.
# Covers what `mix hex.audit` misses: it only flags *retired* packages, while
# advisories on still-published versions (e.g. req CVE-2026-49755) sit in the
# hex.pm API. Run via `mix run --no-start` (no DB/app boot needed).
{:ok, _} = Application.ensure_all_started(:req)
lock = Mix.Dep.Lock.read()

hits =
  for {_, t} when elem(t, 0) == :hex <- lock,
      name = elem(t, 1),
      vsn = elem(t, 2),
      adv <- Req.get!("https://hex.pm/api/packages/#{name}").body["security_advisories"] || [],
      Enum.any?(adv["affected"], &Version.match?(vsn, &1)),
      do: {name, vsn, adv["cvss_rating"], adv["id"], adv["summary"]}

for {name, vsn, rating, id, summary} <- hits do
  IO.puts("✗ #{name} #{vsn} — [#{rating}] #{id}: #{summary}")
  # GitHub Actions annotation (surfaces at the top of the run and inline).
  if System.get_env("GITHUB_ACTIONS"),
    do: IO.puts("::error title=#{name} #{vsn} [#{rating}]::#{id}: #{summary}")
end

# Markdown job summary, rendered on the run page when running in CI.
if (path = System.get_env("GITHUB_STEP_SUMMARY")) && hits != [] do
  rows = for {n, v, r, id, s} <- hits, do: "| #{n} | #{v} | #{r} | #{id} | #{s} |"
  header = "## Vulnerable dependencies\n\n| Package | Version | Severity | Advisory | Summary |\n|--|--|--|--|--|\n"
  File.write!(path, header <> Enum.join(rows, "\n") <> "\n", [:append])
end

if hits == [], do: IO.puts("✓ no known advisories in mix.lock"), else: System.halt(1)
