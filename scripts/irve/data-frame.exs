defmodule DiskStorage do
end

defmodule Demo do
  # https://www.data.gouv.fr/fr/datasets/623ca46c13130c3228abd018/ - Electra dataset (mid-sized)
  # https://www.data.gouv.fr/fr/datasets/623ca46c13130c3228abd018/#/resources/e9bb3424-77cd-40ba-8bbd-5a19362d0365

  @sample_url "https://www.data.gouv.fr/fr/datasets/r/e9bb3424-77cd-40ba-8bbd-5a19362d0365"

  def show_one() do
    # Note: cached in development if you set `irve_consolidation_caching: true` in `dev.secret.exs`
    %Req.Response{status: 200, body: body} =
      Transport.IRVE.Fetcher.get!(@sample_url, compressed: false, decode_body: false)

    Transport.IRVE.DataFrame.dataframe_from_csv_body!(body)
    |> Explorer.DataFrame.select("id_pdc_itinerance")
    |> IO.inspect(IEx.inspect_opts())
  end

  @doc """
  A quick probe to evaluate if a content is likely to be "modern" schema-irve-statique data
  """
  def has_id_pdc_itinerance(body) do
    body
    |> String.split("\n", parts: 2)
    |> hd()
    |> String.contains?("id_pdc_itinerance")
  end

  @doc """
  Relying on a field that was in v1 of the schema, and not in v2, try to hint about old files.

  See https://github.com/etalab/schema-irve/compare/v1.0.3...v2.0.0#diff-9fcde326d127f74194f70e563bdf2c118c51b719c308f015b8eb0204a9a552fbL72
  """
  def probably_v1_schema(body) do
    data = body
    |> String.split("\n", parts: 2)
    |> hd()

    # NOTE: do not use `n_amenageur`, because it will match in both v1 and v2 due to `siren_amenageur`
    !String.contains?(data, "nom_operateur") && String.contains?(data, "n_operateur")
  end

  def process_one(row) do
    try do
      %{status: 200, body: body} = Transport.IRVE.Fetcher.get!(row[:url], compressed: false, decode_body: false)

      # My assumptions on this method are being checked
      if !String.valid?(body) do
        raise("string is not valid (likely utf-8 instead of latin1)")
      end

      if probably_v1_schema(body) do
        raise("looks like a v1 irve")
      end

      if !has_id_pdc_itinerance(body) do
        raise("content has no id_pdc_itinerance in first line")
      end

      df =
        Transport.IRVE.DataFrame.dataframe_from_csv_body!(body, Transport.IRVE.StaticIRVESchema.schema_content(), false)
        |> Transport.IRVE.DataFrame.preprocess_data()
        |> Explorer.DataFrame.select(["id_pdc_itinerance", "x", "y"])

      nil_counts = Explorer.DataFrame.nil_count(df)
      nil_counts = {
        Explorer.Series.at(nil_counts[:id_pdc_itinerance], 0),
        Explorer.Series.at(nil_counts[:x], 0),
        Explorer.Series.at(nil_counts[:y], 0)
      }
      unless nil_counts == {0, 0, 0} do
        IO.puts row.url
        IO.inspect(nil_counts, IEx.inspect_opts)
      end

      {:ok, df}
    rescue
      error ->
        {:error, error}
    end
  end

  def concat_rows(nil, df), do: df
  def concat_rows(main_df, df), do: Explorer.DataFrame.concat_rows(main_df, df)

  defmodule ReportItem do
    @enforce_keys [:dataset_id, :resource_id, :resource_url]
    defstruct [:dataset_id, :resource_id, :resource_url, :error]
  end

  def show_more() do
    Transport.IRVE.Extractor.datagouv_resources()
    # exclude data gouv generated consolidation
    |> Enum.reject(fn r -> r[:dataset_organisation_id] == "646b7187b50b2a93b1ae3d45" end)
    |> Enum.sort_by(fn r -> [r[:dataset_id], r[:resource_id]] end)
    # |> Stream.drop(1001)
    # |> Stream.take(10)
    # |> Enum.filter(&(&1.resource_id == "cbd64933-26df-4ab5-b9e8-104f9af9a16c"))
    |> Enum.reduce(%{df: nil, report: []}, fn row, %{df: main_df, report: report} ->
      {main_df, error} = case process_one(row) do
        {:ok, df} -> {concat_rows(main_df, df), nil}
        {:error, error} -> {main_df, error}
      end

      description = %ReportItem{
        dataset_id: row.dataset_id,
        resource_id: row.resource_id,
        resource_url: row.url,
        error: error
      }

      %{
        df: main_df,
        report: [description | report]
      }
    end)
    |> IO.inspect(IEx.inspect_opts())
    |> then(fn x -> x[:df] end)
    |> Explorer.DataFrame.to_csv!("consolidation.csv")
  end
end

# IO.puts("========== just one sample ==========")

# Demo.show_one()

# IO.puts("========== go further ==========")

Demo.show_more()
