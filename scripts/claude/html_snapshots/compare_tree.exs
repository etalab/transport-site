#! mix run --no-start
# usage: mix run --no-start scripts/claude/html_snapshots/compare_tree.exs <before_dir> <after_dir> [--lines 20] [--mask-digits]
#
# Diffs the canonical form of every page of two snap_suite.sh runs. Canonical form: one tag or text per line,
# sorted attributes (the old helpers sorted them, HEEx keeps template order), whitespace-only text dropped,
# per-request values (CSRF tokens, LiveView sessions, nonces, times) neutralized, database ids and UUIDs
# renumbered by order of appearance. --mask-digits replaces every number by N, to tell factory sequence
# shifts from real changes.

defmodule HTMLSnapshots.Canon do
  @volatile ["data-phx-session", "data-phx-static", "data-phx-id", "data-phx-loc", "data-phx-upload-ref", "nonce"]
  @void ~w(area base br col embed hr img input link meta param source track wbr)
  @renumbered ~r/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|(?<![A-Za-z0-9.])\d{3,}(?![A-Za-z0-9.])/

  def lines(html, opts) do
    out = html |> Floki.parse_document!() |> Enum.flat_map(&canon_node/1) |> Enum.join("\n") |> renumber()
    out = if opts[:mask_digits], do: String.replace(out, ~r/N?\d+/, "N"), else: out
    String.split(out, "\n")
  end

  defp canon_node({tag, attrs, children}) when is_binary(tag) do
    start = Enum.join(["<#{tag}" | attrs(tag, attrs)], " ") <> ">"
    if tag in @void, do: [start], else: [start | Enum.flat_map(children, &canon_node/1)] ++ ["</#{tag}>"]
  end

  defp canon_node(text) when is_binary(text) do
    text =
      text
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()
      |> String.replace(~r/\b\d{2}:\d{2}:\d{2}\b/, "HH:MM:SS")
      |> String.replace(~r/\b\d{1,2}h\d{2}\b/, "HHhMM")

    if text == "", do: [], else: [text]
  end

  # comments, doctype
  defp canon_node(_other), do: []

  defp attrs(tag, attrs) do
    csrf? =
      {"name", "_csrf_token"} in attrs or
        (tag == "meta" and Enum.any?(attrs, &(&1 in [{"name", "csrf-token"}, {"name", "csrf"}])))

    attrs
    |> Enum.map(fn {k, v} ->
      v =
        cond do
          k in @volatile -> "X"
          csrf? and k in ["value", "content"] -> "CSRF"
          Regex.match?(~r/^phx-[A-Za-z0-9_-]+$/, v) -> "phx-X"
          true -> decode(v)
        end

      {k, v}
    end)
    |> Enum.sort()
    |> Enum.map(fn {k, v} -> ~s(#{k}="#{v}") end)
  end

  defp decode(value) do
    URI.decode(value)
  rescue
    ArgumentError -> value
  end

  defp renumber(out) do
    labels =
      @renumbered
      |> Regex.scan(out)
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.with_index(1)
      |> Map.new(fn {match, i} -> {match, "N#{i}"} end)

    Regex.replace(@renumbered, out, &Map.fetch!(labels, &1))
  end
end

{opts, [before_dir, after_dir], []} =
  OptionParser.parse(System.argv(), strict: [lines: :integer, mask_digits: :boolean])

max_lines = Keyword.get(opts, :lines, 20)
pages = Path.wildcard(Path.join(before_dir, "**/*.html")) |> Enum.map(&Path.relative_to(&1, before_dir)) |> Enum.sort()

for page <- pages do
  after_page = Path.join(after_dir, page)

  if File.exists?(after_page) do
    before = before_dir |> Path.join(page) |> File.read!() |> HTMLSnapshots.Canon.lines(opts)
    after_ = after_page |> File.read!() |> HTMLSnapshots.Canon.lines(opts)

    if before != after_ do
      IO.puts("DIFFERENT  #{page}")

      before
      |> List.myers_difference(after_)
      |> Enum.flat_map(fn
        {:eq, _} -> []
        {:del, lines} -> Enum.map(lines, &"< #{&1}")
        {:ins, lines} -> Enum.map(lines, &"> #{&1}")
      end)
      |> Enum.take(max_lines)
      |> Enum.each(&IO.puts/1)
    end
  else
    IO.puts("MISSING    #{page}")
  end
end

IO.puts("pages: #{length(pages)}")
