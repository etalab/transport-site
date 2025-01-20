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

  def first_line(body) do
    body
    |> String.split("\n", parts: 2)
    |> hd()
  end

  @doc """
  A quick probe to evaluate if a content is likely to be "modern" schema-irve-statique data
  """
  def has_id_pdc_itinerance(body) do
    body
    |> first_line()
    |> String.contains?("id_pdc_itinerance")
  end

  @doc """
  Relying on a field that was in v1 of the schema, and not in v2, try to hint about old files.

  See https://github.com/etalab/schema-irve/compare/v1.0.3...v2.0.0#diff-9fcde326d127f74194f70e563bdf2c118c51b719c308f015b8eb0204a9a552fbL72
  """
  def probably_v1_schema(body) do
    data = body |> first_line()

    # NOTE: do not use `n_amenageur`, because it will match in both v1 and v2 due to `siren_amenageur`
    !String.contains?(data, "nom_operateur") && String.contains?(data, "n_operateur")
  end

  def process_one(row) do
    try do
      %{status: 200, body: body} = Transport.IRVE.Fetcher.get!(row.url, compressed: false, decode_body: false)

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

      # TODO: preprocess/conform booleans (`0` -> `FALSE`) so that we can use `strict = true`
      # TODO: be smooth about `cable_t2_attache` - only added in v2.1.0 (https://github.com/etalab/schema-irve/releases/tag/v2.1.0)
      # and often not provided
      df =
        Transport.IRVE.DataFrame.dataframe_from_csv_body!(
          body,
          Transport.IRVE.StaticIRVESchema.schema_content(),
          _strict = false
        )
        # TODO: rename accordingly
        |> Transport.IRVE.DataFrame.preprocess_data()
        # TODO: loop programmatically
        |> Transport.IRVE.DataFrame.preprocess_boolean("prise_type_ef")
        |> Transport.IRVE.DataFrame.preprocess_boolean("prise_type_2")
        |> Transport.IRVE.DataFrame.preprocess_boolean("prise_type_combo_ccs")
        |> Transport.IRVE.DataFrame.preprocess_boolean("prise_type_chademo")
        |> Transport.IRVE.DataFrame.preprocess_boolean("prise_type_autre")
        |> Transport.IRVE.DataFrame.preprocess_boolean("gratuit")
        |> Transport.IRVE.DataFrame.preprocess_boolean("paiement_acte")
        |> Transport.IRVE.DataFrame.preprocess_boolean("paiement_cb")
        |> Transport.IRVE.DataFrame.preprocess_boolean("paiement_autre")
        |> Transport.IRVE.DataFrame.preprocess_boolean("reservation")
        |> Transport.IRVE.DataFrame.preprocess_boolean("station_deux_roues")
        |> Explorer.DataFrame.select([
          "nom_amenageur",
          "siren_amenageur",
          "contact_amenageur",
          "nom_operateur",
          "contact_operateur",
          "telephone_operateur",
          "nom_enseigne",
          "id_station_itinerance",
          "id_station_local",
          "nom_station",
          "implantation_station",
          "adresse_station",
          "code_insee_commune",
          # "coordonneesXY",
          "nbre_pdc",
          "id_pdc_itinerance",
          "id_pdc_local",
          "puissance_nominale",
          "prise_type_ef",
          "prise_type_2",
          "prise_type_combo_ccs",
          "prise_type_chademo",
          "prise_type_autre",
          "gratuit",
          "paiement_acte",
          "paiement_cb",
          "paiement_autre",
          "tarification",
          "condition_acces",
          "reservation",
          "horaires",
          "accessibilite_pmr",
          "restriction_gabarit",
          "station_deux_roues",
          "raccordement",
          "num_pdl",
          "date_mise_en_service",
          "observations",
          "date_maj",
          # "cable_t2_attache",
          # extracted
          "x",
          "y"
        ])

      nil_counts = Explorer.DataFrame.nil_count(df)

      nil_counts = {
        Explorer.Series.at(nil_counts[:id_pdc_itinerance], 0),
        Explorer.Series.at(nil_counts[:x], 0),
        Explorer.Series.at(nil_counts[:y], 0)
      }

      unless nil_counts == {0, 0, 0} do
        IO.puts(row.url)
        IO.inspect(nil_counts, IEx.inspect_opts())
      end

      {:ok, df}
    rescue
      error ->
        if String.contains?(error |> inspect, "KeyError") do
          IO.inspect(%{error: error, row: row}, IEx.inspect_opts())
        end

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
    output =
      Transport.IRVE.Extractor.datagouv_resources()
      # exclude data gouv generated consolidation
      |> Enum.reject(fn r -> r.dataset_organisation_id == "646b7187b50b2a93b1ae3d45" end)
      |> Enum.sort_by(fn r -> [r.dataset_id, r.resource_id] end)
      # |> Stream.drop(1001)
      # |> Stream.take(10)
      # |> Enum.filter(&(&1.resource_id == "cbd64933-26df-4ab5-b9e8-104f9af9a16c"))
      |> Enum.reduce(%{df: nil, report: []}, fn row, %{df: main_df, report: report} ->
        {main_df, error} =
          case process_one(row) do
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

    output.df
    |> Explorer.DataFrame.to_csv!("consolidation.csv")

    output.report
    |> Enum.reverse()
    |> Enum.map(&Map.from_struct/1)
    |> Enum.map(fn x -> Map.put(x, :error, x.error |> inspect) end)
    |> Explorer.DataFrame.new()
    |> Explorer.DataFrame.to_csv!("report.csv")
  end
end

# IO.puts("========== just one sample ==========")

# Demo.show_one()

# IO.puts("========== go further ==========")

Demo.show_more()
