# Run with:
# elixir generate_deps_changelogs.exs
#
# This is a quick script to generate changelogs on screen, comparing `mix.lock` on current branch vs `master`.
# It makes it easier to review changes provided by a given PR. Yes, dependabot exists,
# but does not support grouped updates (https://github.com/dependabot/dependabot-core/issues/1190)
# and does not work well on an existing PR.
#
# Already used in the past, and if useful on the long run, we'll create a GitHub action workflow to run
# and automatically edit the PR description with this.
#

defmodule Scanner do
  def scan(mix_lock_content) do
    {lock_deps, []} = mix_lock_content |> Code.eval_string()

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

IO.puts "### Changelogs\n"

master
|> Enum.each(fn {dep, old} ->
  new = Keyword.get(current, dep)

  diff =
    case {old, new} do
      {{:hex, v1}, {:hex, v2}} ->
        if v1 != v2 do
          IO.puts("* https://diff.hex.pm/diff/#{dep}/#{v1}..#{v2}")
        end

      {{:git, repo, sha1}, {:git, _repo, sha2}} ->
        if sha1 != sha2 do
          compare = repo |> String.replace(".git", "/compare/#{sha1}..#{sha2}")
          IO.puts("* #{compare}")
        end
    end
end)
