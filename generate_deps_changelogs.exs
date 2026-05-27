# Run with:
# elixir generate_deps_changelogs.exs
#
# This is a quick script to generate changelogs on screen, comparing `mix.lock` and `yarn.lock`
# on current branch vs `master`. It makes it easier to review changes provided by a given PR.
# Yes, dependabot exists, but does not support grouped updates
# (https://github.com/dependabot/dependabot-core/issues/1190) and does not work well on an existing PR.
#
# Already used in the past, and if useful on the long run, we'll create a GitHub action workflow to run
# and automatically edit the PR description with this.
#

Mix.install([:jason])

defmodule Scanner do
  def scan(mix_lock_content) do
    {{lock_deps, []}, _diagnostics} =
      Code.with_diagnostics(fn -> Code.eval_string(mix_lock_content) end)

    lock_deps
    |> Enum.map(fn {entry, data} ->
      case data do
        {:hex, entry, version, _sha, _tool, _deps, "hexpm", _other_sha} ->
          {entry, {:hex, version}}

        {:git, repo, git_sha, _spec} ->
          {entry, {:git, repo, git_sha}}
      end
    end)
    |> Enum.sort()
  end
end

{master_mix_lock, 0} = System.cmd("git", ["show", "master:mix.lock"])
master = Scanner.scan(master_mix_lock)
current = Scanner.scan(File.read!("./mix.lock"))

IO.puts "(initially generated with `elixir generate_deps_changelogs.exs`)\n"
IO.puts "### Elixir dependencies\n"

master
|> Enum.each(fn {dep, old} ->
  new = Keyword.get(current, dep)

  case {old, new} do
      {{:hex, v1}, {:hex, v2}} ->
        if v1 != v2 do
          IO.puts("* https://diff.hex.pm/diff/#{dep}/#{v1}..#{v2}")
        end

      {{:git, repo, sha1}, {:git, repo_next, sha2}} ->
        if sha1 != sha2 do
          if repo == repo_next do
            compare = repo |> String.replace(".git", "/compare/#{sha1}..#{sha2}")
            IO.puts("* #{compare}")
          else
            repo = repo |> String.replace(".git", "")
            repo_next = repo_next |> String.replace(".git", "")
            IO.puts "* From #{repo}/commit/#{sha1} to #{repo_next}/commit/#{sha2}"
          end
        end
      {{:hex, _v1}, {:git, repo, sha2}} ->
        IO.puts("* Now using git-version #{repo} @ #{sha2}")
      {{:git, repo, sha1}, {:hex, _v2}} ->
        IO.puts("* Now using https://hex.pm/packages/#{dep} instead of #{repo} @ #{sha1}")
      {{:hex, v1}, nil} ->
        IO.puts("* REMOVED: #{dep}@#{v1}")
    end
end)

defmodule YarnScanner do
  @path "apps/transport/client"

  # name => sorted unique list of resolved versions (a name may appear at
  # several versions, since we bundle multiple versions at times).
  def versions(:local), do: parse(File.read!("#{@path}/yarn.lock"))

  def versions(ref) do
    {yl, 0} = System.cmd("git", ["show", "#{ref}:#{@path}/yarn.lock"])
    parse(yl)
  end

  # Names declared top-level in a ref's package.json (deps / devDeps /
  # resolutions). Used only to classify a dep into the top-level vs the
  # transitive section — not to filter anything out.
  def direct(:local), do: parse_direct(File.read!("#{@path}/package.json"))

  def direct(ref) do
    {pj, 0} = System.cmd("git", ["show", "#{ref}:#{@path}/package.json"])
    parse_direct(pj)
  end

  defp parse_direct(json) do
    json
    |> Jason.decode!()
    |> Map.take(~w(dependencies devDependencies resolutions))
    |> Map.values()
    |> Enum.flat_map(&Map.keys/1)
    |> MapSet.new()
  end

  # npmdiff.dev diffs the published tarballs (the npm equivalent of
  # diff.hex.pm). Scoped names need the scope slash percent-encoded.
  def diff_url(name, v1, v2) do
    "https://npmdiff.dev/#{String.replace(name, "/", "%2F")}/#{v1}/#{v2}/"
  end

  defp parse(lock) do
    lock
    |> String.split("\n\n")
    |> Enum.reduce(%{}, fn block, acc ->
      with [_, name] <- Regex.run(~r/^"?((?:@[^\/"]+\/)?[^@"\s]+)@/m, block),
           [_, ver] <- Regex.run(~r/version "([^"]+)"/, block) do
        Map.update(acc, name, [ver], &Enum.uniq([ver | &1]))
      else
        _ -> acc
      end
    end)
    |> Map.new(fn {name, vers} -> {name, Enum.sort(vers)} end)
  end
end

yarn_master = YarnScanner.versions("master")
yarn_current = YarnScanner.versions(:local)
# Union of both refs so a name dropped from resolutions on one side is still
# classified the same way.
direct = MapSet.union(YarnScanner.direct("master"), YarnScanner.direct(:local))

# Same treatment for everyone; only the section a line lands in differs.
render = fn name ->
  case {Map.get(yarn_master, name), Map.get(yarn_current, name)} do
    {same, same} ->
      nil

    {nil, news} ->
      "* ADDED: #{name}@#{Enum.join(news, ", ")}"

    {olds, nil} ->
      "* REMOVED: #{name}@#{Enum.join(olds, ", ")}"

    {[old], [new]} ->
      "* #{YarnScanner.diff_url(name, old, new)}"

    {olds, news} ->
      # Multi-version (bundled duplicates): no single tarball diff applies.
      "* #{name}: #{Enum.join(olds, ", ")} → #{Enum.join(news, ", ")}"
  end
end

{top_level, lock_only} =
  (Map.keys(yarn_master) ++ Map.keys(yarn_current))
  |> Enum.uniq()
  |> Enum.sort()
  |> Enum.map(&{&1, render.(&1)})
  |> Enum.reject(fn {_name, line} -> is_nil(line) end)
  |> Enum.split_with(fn {name, _line} -> MapSet.member?(direct, name) end)

IO.puts "\n### JS dependencies — top-level (package.json: dependencies / devDependencies / resolutions)\n"
Enum.each(top_level, fn {_name, line} -> IO.puts(line) end)

IO.puts "\n### JS dependencies — transitive (yarn.lock only)"
IO.puts "(may include duplicates, since we bundle multiple versions at times)\n"
Enum.each(lock_only, fn {_name, line} -> IO.puts(line) end)
