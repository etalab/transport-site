# Scans every resource of the IRVE static consolidation report for encoding problems: files mixing UTF-8 and 8-bit
# encodings (scope: header, file, line or cell), and failed re-encodings (mojibake) inside valid UTF-8.
#
# elixir scripts/irve/encoding-scan.exs [REPORT_URL_OR_PATH CACHE_DIR OUTPUT_CSV]
#
# Defaults: the live consolidation report, cache in scripts/irve/cache-dir/encoding-scan (one file per resource_id,
# delete the folder to download everything again), output in scripts/irve/cache-dir/encoding-scan.csv.
Mix.install([:req])

defmodule EncodingDiag do
  # CP1252 0x80-0x9F (5 undefined slots skipped)
  @cp1252 Enum.zip(
            String.to_charlist("€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ"),
            [0x80 | Enum.to_list(0x82..0x8C)] ++ [0x8E | Enum.to_list(0x91..0x9C)] ++ [0x9E, 0x9F]
          )
          |> Map.new()
  @mac_roman "ÄÅÇÉÑÖÜáàâäãåçéèêëíìîïñóòôöõúùûü†°¢£§•¶ß®©™´¨≠ÆØ∞±≤≥¥µ∂∑∏π∫ªºΩæø" <>
               "¿¡¬√ƒ≈∆«»… ÀÃÕŒœ–—“”‘’÷◊ÿŸ⁄€‹›ﬁﬂ‡·‚„‰ÂÊÁËÈÍÎÏÌÓÔÒÚÛÙıˆ˜¯˘˙˚¸˝˛ˇ"
  @mac_roman_map String.to_charlist(@mac_roman) |> Enum.zip(0x80..0xFF) |> Map.new()
  128 = map_size(@mac_roman_map)
  # non-ASCII chars expected in French IRVE text
  @french "àâäçéèêëîïôöùûüÿœæÀÂÄÇÉÈÊËÎÏÔÖÙÛÜŸŒÆ€’‘“”–—…°«»² "
  @french_run Regex.compile!("^[#{@french}]+$", "u")
  @plausible_fix Regex.compile!("^[a-zA-Z#{@french}]+$", "u")
  # bytes of é, è, à in each 8-bit encoding (DOS = CP850/437)
  @flavours %{"latin1/cp1252" => [0xE9, 0xE8, 0xE0], "mac_roman" => [0x8E, 0x8F, 0x88], "dos" => [0x82, 0x8A, 0x85]}

  defp runs(text), do: Regex.scan(~r/[^\x00-\x7F]+/u, text) |> List.flatten()

  @doc "Raw bytes: :ascii | :utf8 | :\"8bit\" | :mixed. Next to 8-bit bytes, only plausible French UTF-8 counts as UTF-8."
  def kind(bin) do
    chunks = String.chunk(bin, :valid)
    bit8? = Enum.any?(chunks, &(not String.valid?(&1)))
    utf8? = Enum.any?(chunks, &(String.valid?(&1) and Enum.any?(runs(&1), fn r -> not bit8? or r =~ @french_run end)))

    Map.fetch!(
      %{{false, false} => :ascii, {true, false} => :utf8, {false, true} => :"8bit", {true, true} => :mixed},
      {utf8?, bit8?}
    )
  end

  @doc "On valid UTF-8 text: [{run, repaired, depth}] for runs that re-decode as French once read back as latin-1/CP1252/Mac Roman"
  def mojibake(text) do
    for [run] <- Regex.scan(~r/[a-zA-Z]?[^\x00-\x7F]{2,}/u, text),
        {fixed, depth} = unwind(run, 0),
        fixed = String.normalize(fixed, :nfc),
        depth > 0 and fixed =~ @plausible_fix and fixed != run,
        do: {run, fixed, depth}
  end

  defp unwind(s, depth) do
    Enum.find_value([@cp1252, @mac_roman_map], {s, depth}, fn table ->
      bytes = to_8bit(s, table)
      if is_binary(bytes) and String.valid?(bytes), do: unwind(bytes, depth + 1)
    end)
  end

  # chars <= 0xFF map to themselves for latin-1/CP1252; Mac Roman maps only its high half
  defp to_8bit(s, table) do
    Enum.reduce_while(String.to_charlist(s), <<>>, fn c, acc ->
      b = if c < 0x80 or (c <= 0xFF and table != @mac_roman_map), do: c, else: table[c]
      if b, do: {:cont, <<acc::binary, b>>}, else: {:halt, nil}
    end)
  end

  # NUL bytes: zip/xlsx/parquet served as CSV, out of scope here
  def scan(body) when binary_part(body, 0, 2) == "PK" or binary_part(body, 0, 4) == "PAR1", do: %{kind: :binary}

  def scan(body) do
    {valid, invalid} = body |> String.chunk(:valid) |> Enum.split_with(&String.valid?/1)
    valid_text = Enum.join(valid, "\n")
    moji = mojibake(valid_text)
    other_utf8 = valid_text |> runs() |> Enum.reject(&(&1 =~ @french_run))

    Map.merge(
      if(invalid == [], do: %{}, else: mixed_details(body, invalid)),
      %{
        kind: kind(body),
        mojibake_runs: length(moji),
        mojibake_max_depth: moji |> Enum.map(&elem(&1, 2)) |> Enum.max(fn -> 0 end),
        mojibake_samples:
          moji
          |> Enum.frequencies()
          |> Enum.sort_by(&(-elem(&1, 1)))
          |> Enum.take(5)
          |> Enum.map_join(" · ", fn {{r, f, d}, n} -> "#{r}→#{f} (x#{d}) ×#{n}" end),
        replacement_chars: Enum.count(other_utf8, &String.contains?(&1, ["�", "ï¿½"])),
        c1_controls: length(Regex.scan(~r/[\x{80}-\x{9F}]/u, valid_text)),
        other_utf8_samples:
          other_utf8
          |> Enum.frequencies()
          |> Enum.sort_by(&(-elem(&1, 1)))
          |> Enum.take(3)
          |> Enum.map_join(" ", fn {r, n} -> "#{r}×#{n}" end)
      }
    )
  end

  # only for files with invalid UTF-8: where does the mix happen, and which 8-bit encoding
  defp mixed_details(body, invalid) do
    lines = String.split(body, "\n")
    sep = if String.contains?(hd(lines), ";"), do: ";", else: ","
    kinds = lines |> Enum.with_index(1) |> Enum.map(fn {l, i} -> {i, kind(l)} end)
    mixed_lines = for {i, :mixed} <- kinds, do: i
    count = fn k -> Enum.count(kinds, &(elem(&1, 1) == k)) end
    mixed_cells = for i <- mixed_lines, c <- String.split(Enum.at(lines, i - 1), sep), kind(c) == :mixed, do: c
    freq = invalid |> Enum.join() |> :binary.bin_to_list() |> Enum.frequencies()

    scope =
      cond do
        mixed_cells != [] -> "cellule"
        mixed_lines != [] -> "ligne"
        for({1, :utf8} <- kinds, do: 1) != [] and count.(:utf8) == 1 -> "en-tête"
        count.(:utf8) > 0 -> "fichier"
        true -> ""
      end

    %{
      mix_scope: scope,
      eight_bit_flavour:
        Enum.max_by(@flavours, fn {_, bytes} -> Enum.sum_by(bytes, &Map.get(freq, &1, 0)) end) |> elem(0),
      lines_8bit: count.(:"8bit"),
      lines_utf8: count.(:utf8),
      lines_mixed: length(mixed_lines),
      cells_mixed: length(mixed_cells),
      first_mixed_lines: mixed_lines |> Enum.take(3) |> Enum.join(" "),
      mixed_cell_sample: mixed_cells |> List.first("") |> inspect(binaries: :as_strings) |> String.slice(0, 120)
    }
  end
end

defmodule Main do
  @cols ~w(resource_id dataset_id datagouv_organization_or_owner consolidation_status kind mix_scope eight_bit_flavour lines_8bit lines_utf8 lines_mixed cells_mixed first_mixed_lines mixed_cell_sample mojibake_runs mojibake_max_depth mojibake_samples replacement_chars c1_controls other_utf8_samples error url)a

  # minimal CSV (quoted fields) reader, good enough for the report
  def parse_csv(body) do
    ~r/("(?:[^"]|"")*"|[^,\n]*)(,|\n|$)/
    |> Regex.scan(body)
    |> Enum.chunk_while(
      [],
      fn [_, f, sep], acc ->
        acc = [unquote_field(f) | acc]
        if sep == ",", do: {:cont, acc}, else: {:cont, Enum.reverse(acc), []}
      end,
      &{:cont, &1}
    )
    |> Enum.reject(&(&1 == [""]))
  end

  defp unquote_field(~s(") <> _ = f), do: f |> String.slice(1..-2//1) |> String.replace(~s(""), ~s("))
  defp unquote_field(f), do: f

  defp quote_field(v), do: ~s(") <> String.replace(to_string(v), ~s("), ~s("")) <> ~s(")

  def fetch("", _path), do: {:error, "no url"}

  def fetch(url, path) do
    if File.exists?(path) do
      {:ok, File.read!(path), :cached}
    else
      case Req.get(url, decode_body: false, receive_timeout: 300_000) do
        {:ok, %{status: 200, body: body}} ->
          File.write!(path, body)
          {:ok, body, :downloaded}

        {:ok, %{status: status}} ->
          {:error, "HTTP #{status}"}

        {:error, e} ->
          {:error, Exception.message(e)}
      end
    end
  end

  def scan_row(r, cache_dir) do
    result =
      case fetch(r["url"], Path.join(cache_dir, r["resource_id"])) do
        {:ok, "", source} -> %{error: "empty", fetched: source}
        {:ok, body, source} -> scan_or_error(body) |> Map.put(:fetched, source)
        {:error, e} -> %{error: e, fetched: :failed}
      end

    r |> Map.new(fn {k, v} -> {String.to_atom(k), v} end) |> Map.merge(result)
  end

  defp scan_or_error(body) do
    EncodingDiag.scan(body)
  rescue
    e -> %{error: Exception.message(e)}
  end

  def run([]) do
    run([
      "https://proxy.transport.data.gouv.fr/resource/consolidation-transport-irve-statique-rapport",
      Path.join(__DIR__, "cache-dir/encoding-scan"),
      Path.join(__DIR__, "cache-dir/encoding-scan.csv")
    ])
  end

  def run([report, cache_dir, output]) do
    File.mkdir_p!(cache_dir)

    body =
      if String.starts_with?(report, "http"), do: Req.get!(report, decode_body: false).body, else: File.read!(report)

    [header | rows] = parse_csv(body)
    total = length(rows)
    IO.puts("cache: #{cache_dir} (rm -rf it to download everything again, or delete one resource_id file)")

    {results, _counts} =
      rows
      |> Enum.map(&(header |> Enum.zip(&1) |> Map.new()))
      |> Task.async_stream(&scan_row(&1, cache_dir), max_concurrency: 8, timeout: :infinity, ordered: false)
      |> Enum.map_reduce(%{cached: 0, downloaded: 0, failed: 0}, fn {:ok, r}, counts ->
        counts = Map.update!(counts, r.fetched, &(&1 + 1))
        done = counts.cached + counts.downloaded + counts.failed

        IO.write(
          "\r#{done}/#{total} · cached #{counts.cached} · downloaded #{counts.downloaded} · failed #{counts.failed}"
        )

        {r, counts}
      end)

    IO.puts("\n")

    lines = Enum.map(results, fn r -> Enum.map_join(@cols, ",", &quote_field(Map.get(r, &1, ""))) end)
    File.write!(output, Enum.join([Enum.join(@cols, ",") | lines], "\n") <> "\n")
    print_summary(results, output)
  end

  defp print_summary(results, output) do
    in_consolidation? = &(&1.consolidation_status in ~w(already_up_to_date import_successful))
    IO.puts("#{length(results)} resources scanned, details in #{output}")
    IO.puts("by kind: #{inspect(Enum.frequencies_by(results, &Map.get(&1, :kind, :error)))}")

    for {title, legend, hit?} <- [
          {"Mixed encodings",
           "file mixing UTF-8 and 8-bit bytes, shown as finest scope (header/file/line/cell) and 8-bit encoding",
           &(&1[:kind] == :mixed)},
          {"Mojibake in valid UTF-8",
           "UTF-8 text once read back as latin-1/CP1252/Mac Roman and saved again (é → Ã© or √©), " <>
             "shown as found→repaired (xN wrong re-reads) ×occurrences", &(Map.get(&1, :mojibake_runs, 0) > 0)}
        ] do
      hits = Enum.filter(results, hit?)
      IO.puts("\n#{title}: #{length(hits)} resources, #{Enum.count(hits, in_consolidation?)} in the consolidation")
      IO.puts("  (#{legend})")

      hits
      |> Enum.filter(in_consolidation?)
      |> Enum.group_by(& &1.datagouv_organization_or_owner)
      |> Enum.sort()
      |> Enum.each(fn {org, [r | _] = rs} ->
        IO.puts("  #{org} (#{length(rs)}): #{r[:mix_scope]} #{r[:eight_bit_flavour]} #{r[:mojibake_samples]}")
      end)
    end
  end
end

Main.run(System.argv())
