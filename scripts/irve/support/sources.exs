# Helpers shared by the IRVE comparison scripts (compare.exs, afirev.exs), loaded with `Code.require_file/2`.
# Not meant to be run on its own.

defmodule IRVEScripts.Sources do
  alias Explorer.DataFrame, as: DF
  alias Explorer.Series

  @proxy "https://proxy.transport.data.gouv.fr/resource"
  @aliases %{
    "transport" => "#{@proxy}/consolidation-transport-irve-statique",
    "transport-avec-doublons" => "#{@proxy}/consolidation-transport-avec-doublons-irve-statique",
    "datagouv" => "https://www.data.gouv.fr/api/1/datasets/r/eb76d20a-8501-400e-b336-d85724de5435"
  }

  def cache_dir, do: Path.expand("../../../cache-dir/irve", __DIR__)

  @doc "Source alias, URL or local path → local CSV path."
  def resolve(source) do
    cond do
      Map.has_key?(@aliases, source) ->
        cached_download!(source, @aliases[source], "csv")

      String.starts_with?(source, ["http://", "https://"]) ->
        hash = :crypto.hash(:sha256, source) |> Base.encode16(case: :lower) |> binary_part(0, 12)
        cached_download!("url-#{hash}", source, "csv")

      File.exists?(source) ->
        source

      true ->
        raise ArgumentError, "unknown source #{inspect(source)}, aliases are: #{Map.keys(@aliases) |> Enum.join(", ")}"
    end
  end

  @doc "Downloads once a day into the cache dir, returns the local path."
  def cached_download!(name, url, extension) do
    path = Path.join(cache_dir(), "#{name}-#{Date.utc_today()}.#{extension}")

    if File.exists?(path) do
      IO.puts("Using #{Path.relative_to_cwd(path)}")
    else
      IO.puts("Downloading #{url} → #{Path.relative_to_cwd(path)}")
      {:ok, _} = Application.ensure_all_started(:req)
      File.mkdir_p!(cache_dir())
      part = path <> ".part"

      %{status: 200} =
        Req.get!(url,
          into: File.stream!(part),
          compressed: false,
          redirect_log_level: false,
          receive_timeout: :timer.minutes(2)
        )

      File.rename!(part, path)
    end

    path
  end

  @doc """
  Loads the given CSV columns as strings, plus `prefix` (operator prefix of `id_pdc_itinerance`, any country)
  and `prefix_bucket` (see `prefix_bucket/1`).
  """
  def load(path, columns) do
    df = DF.from_csv!(path, columns: columns, infer_schema_length: 0)
    {buckets, prefixes} = df["id_pdc_itinerance"] |> Series.to_list() |> Enum.map(&prefix_bucket/1) |> Enum.unzip()

    df
    |> DF.put("prefix_bucket", Series.from_list(buckets))
    |> DF.put("prefix", Series.from_list(prefixes, dtype: :string))
  end

  @doc """
  `{bucket, prefix}` of an `id_pdc_itinerance`, ignoring case and `*`, `-` and blank separators.

      iex> IRVEScripts.Sources.prefix_bucket("fr*abc*e123")
      {"FR", "FRABC"}
      iex> IRVEScripts.Sources.prefix_bucket("ESZUNE1")
      {"foreign", "ESZUN"}
      iex> IRVEScripts.Sources.prefix_bucket("Non concerné")
      {"non concerné", nil}
  """
  def prefix_bucket(nil), do: {"unparseable", nil}

  def prefix_bucket(id) do
    normalized = id |> String.upcase() |> String.replace(~r/[*\-\s]/u, "")

    if String.starts_with?(normalized, "NONCONCERN") do
      {"non concerné", nil}
    else
      case Regex.run(~r/^([A-Z]{2})[A-Z0-9]{3}/, normalized) do
        [prefix, "FR"] -> {"FR", prefix}
        [prefix, _country] -> {"foreign", prefix}
        nil -> {"unparseable", nil}
      end
    end
  end
end
