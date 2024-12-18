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

  def process_one(row) do
    try do
      %{status: 200, body: body} = Transport.IRVE.Fetcher.get!(row[:url], compressed: false, decode_body: false)

      if !has_id_pdc_itinerance(body), do: raise("content has no id_pdc_itinerance in first line")

      df =
        Transport.IRVE.DataFrame.dataframe_from_csv_body!(body, Transport.IRVE.StaticIRVESchema.schema_content(), false)
        |> Explorer.DataFrame.select("id_pdc_itinerance")

      {:ok, df}
    rescue
      error ->
        IO.inspect(error, IEx.inspect_opts())
        {:error, error}
    end
  end

  def concat_rows(nil, df), do: df
  def concat_rows(main_df, df), do: Explorer.DataFrame.concat_rows(main_df, df)

  def show_more() do
    Transport.IRVE.Extractor.datagouv_resources()
    # exclude data gouv generated consolidation
    |> Enum.reject(fn r -> r[:dataset_organisation_id] == "646b7187b50b2a93b1ae3d45" end)
    |> Enum.sort_by(fn r -> [r[:dataset_id], r[:resource_id]] end)
    #    |> Stream.take(3)
    |> Enum.reduce(%{df: nil, report: []}, fn row, %{df: main_df} = acc ->
      case process_one(row) do
        {:ok, df} ->
          acc
          |> Map.put(:df, concat_rows(main_df, df))

        {:error, error} ->
          acc
      end
    end)
    |> IO.inspect(IEx.inspect_opts())
    |> then(fn x -> x[:df] end)
    |> Explorer.DataFrame.to_csv!("consolidation.csv")
  end
end

IO.puts("========== just one sample ==========")

Demo.show_one()

IO.puts("========== go further ==========")

Demo.show_more()
