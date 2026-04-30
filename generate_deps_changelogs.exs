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

Mix.install([:jason, :req])

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

  def at(:local),
    do: parse(File.read!("#{@path}/yarn.lock"), File.read!("#{@path}/package.json"))

  def at(ref) do
    {pj, 0} = System.cmd("git", ["show", "#{ref}:#{@path}/package.json"])
    {yl, 0} = System.cmd("git", ["show", "#{ref}:#{@path}/yarn.lock"])
    parse(yl, pj)
  end

  def diff_url(name, v1, v2) do
    with {:ok, %{status: 200, body: body}} <- Req.get("https://registry.npmjs.org/#{name}"),
         url <- get_in(body, ["repository", "url"]) || "",
         [_, owner, repo] <- Regex.run(~r{github\.com[/:]([^/]+)/([^/.]+)}, url) do
      "https://github.com/#{owner}/#{repo}/compare/v#{v1}...v#{v2}"
    else
      _ -> "https://www.npmjs.com/package/#{name}?activeTab=versions"
    end
  end

  defp parse(lock, json) do
    direct =
      json
      |> Jason.decode!()
      |> Map.take(~w(dependencies devDependencies resolutions))
      |> Map.values()
      |> Enum.flat_map(&Map.keys/1)
      |> MapSet.new()

    lock
    |> String.split("\n\n")
    |> Enum.reduce(%{}, fn block, acc ->
      with [_, name] <- Regex.run(~r/^"?((?:@[^\/"]+\/)?[^@"\s]+)@/m, block),
           true <- MapSet.member?(direct, name),
           [_, ver] <- Regex.run(~r/version "([^"]+)"/, block) do
        Map.put(acc, name, ver)
      else
        _ -> acc
      end
    end)
  end
end

IO.puts "\n### JS dependencies (top-level only)"
IO.puts "(may include duplicates, since we bundle multiple versions at times)\n"
yarn_master = YarnScanner.at("master")
yarn_current = YarnScanner.at(:local)

(Map.keys(yarn_master) ++ Map.keys(yarn_current))
|> Enum.uniq()
|> Enum.sort()
|> Enum.each(fn name ->
  case {yarn_master[name], yarn_current[name]} do
    {v1, v2} when not is_nil(v1) and not is_nil(v2) and v1 != v2 ->
      IO.puts "* #{YarnScanner.diff_url(name, v1, v2)}"
    {nil, v2} when not is_nil(v2) -> IO.puts "* ADDED: #{name}@#{v2}"
    {v1, nil} when not is_nil(v1) -> IO.puts "* REMOVED: #{name}@#{v1}"
    _ -> :ok
  end
end)
