defmodule Transport.Jobs.BaseGeoData do
  @moduledoc """
  Shared methods for GeoData import jobs.

  Provides methods to import/replace data for:
  - consolidated datasets which should be replaced when we have a newer resource history
  - anything else, identified by a slug, which should be replaced everytime
  """
  require Logger

  @import_timeout :timer.seconds(60)
  @consolidated_datasets_slugs Transport.ConsolidatedDataset.geo_data_datasets()

  def insert_data(geo_data_import_id, prepare_data_for_insert_fn) do
    prepare_data_for_insert_fn.(geo_data_import_id)
    |> Stream.each(&DB.Repo.insert_all(DB.GeoData, &1))
    |> Stream.run()
  end

  def insert_data(body, geo_data_import_id, prepare_data_for_insert_fn) do
    body
    |> prepare_data_for_insert_fn.(geo_data_import_id)
    |> Stream.chunk_every(1_000)
    |> Stream.each(&DB.Repo.insert_all(DB.GeoData, &1))
    |> Stream.run()
  end

  defp needs_import?(
         %DB.ResourceHistory{id: latest_resource_history_id},
         %DB.GeoDataImport{resource_history_id: resource_history_id}
       ),
       do: latest_resource_history_id != resource_history_id

  defp needs_import?(_, nil), do: true

  # For a static resource, associated to a consolidated dataset (BNLC, BNZFE, IRVE etc)
  # We rely on the relevant `DB.ResourceHistory` to determine if we should replace the data.
  def import_replace_data(slug, prepare_data_for_insert_fn) when slug in @consolidated_datasets_slugs do
    %DB.Resource{id: resource_id, dataset_id: dataset_id} = Transport.ConsolidatedDataset.resource(slug)
    latest_resource_history = DB.ResourceHistory.latest_resource_history(resource_id)
    current_geo_data_import = DB.GeoDataImport.dataset_latest_geo_data_import(dataset_id)

    if needs_import?(latest_resource_history, current_geo_data_import) do
      Logger.info("New content detected...update content")
      perform_import(current_geo_data_import, latest_resource_history, slug, prepare_data_for_insert_fn)
    end

    :ok
  end

  # For a non-static resource: we don't rely on a `DB.ResourceHistory` associated to a static
  # resource to determine if we should replace the data, it should always be replaced.
  def import_replace_data(slug, prepare_data_for_insert_fn) when is_atom(slug) do
    current_geo_data_import = DB.Repo.get_by(DB.GeoDataImport, slug: slug)

    Logger.info("geo_data for a slug is always replaced… Updating content for #{slug}")
    perform_import(current_geo_data_import, slug, prepare_data_for_insert_fn)

    :ok
  end

  # For a consolidated dataset, we rely on the latest resource history content to perform the import.
  defp perform_import(
         current_geo_data_import,
         %DB.ResourceHistory{id: latest_resource_history_id, payload: %{"permanent_url" => permanent_url}},
         slug,
         prepare_data_for_insert_fn
       )
       when slug in @consolidated_datasets_slugs do
    DB.Repo.transaction(
      fn ->
        unless is_nil(current_geo_data_import) do
          # Thanks to cascading delete, it will also clean geo_data table corresponding entries
          current_geo_data_import |> DB.Repo.delete!()
        end

        %{id: geo_data_import_id} =
          %DB.GeoDataImport{resource_history_id: latest_resource_history_id, slug: slug} |> DB.Repo.insert!()

        http_client = Transport.Shared.Wrapper.HTTPoison.impl()
        %HTTPoison.Response{status_code: 200, body: body} = http_client.get!(permanent_url)
        insert_data(body, geo_data_import_id, prepare_data_for_insert_fn)
      end,
      timeout: @import_timeout
    )
  end

  defp perform_import(current_geo_data_import, slug, prepare_data_for_insert_fn) when is_atom(slug) do
    DB.Repo.transaction(
      fn ->
        unless is_nil(current_geo_data_import) do
          # Thanks to cascading delete, it will also clean geo_data table corresponding entries
          current_geo_data_import |> DB.Repo.delete!()
        end

        %DB.GeoDataImport{id: geo_data_import_id} = DB.Repo.insert!(%DB.GeoDataImport{slug: slug})
        insert_data(geo_data_import_id, prepare_data_for_insert_fn)
      end,
      timeout: @import_timeout
    )
  end

  def prepare_csv_data_for_import(body, prepare_data_fn, opts \\ []) do
    opts = Keyword.validate!(opts, separator_char: ?,, escape_char: ?", filter_fn: fn _ -> true end)
    {:ok, stream} = StringIO.open(body)

    stream
    |> IO.binstream(:line)
    |> CSV.decode(
      separator: Keyword.fetch!(opts, :separator_char),
      escape_character: Keyword.fetch!(opts, :escape_char),
      headers: true,
      validate_row_length: true
    )
    |> Stream.filter(Keyword.fetch!(opts, :filter_fn))
    |> Stream.map(fn {:ok, m} -> m end)
    |> Stream.map(prepare_data_fn)
  end

  # keep 6 digits for WGS 84, see https://en.wikipedia.org/wiki/Decimal_degrees#Precision
  def parse_coordinate(s) do
    s |> string_to_float() |> Float.round(6)
  end

  # remove spaces (U+0020) and non-break spaces (U+00A0) from the string
  defp string_to_float(s), do: s |> String.trim() |> String.replace([" ", " "], "") |> String.to_float()
end
