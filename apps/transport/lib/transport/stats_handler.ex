defmodule Transport.StatsHandler do
  @moduledoc """
  Compute statistics on the datasets. These stats are used to populate the stats page.
  One part (upper part of the module) is called by the stats page controller directly.
  The other part (bottom part) is called by the JS maps of the page through the API stats controller.
  Also contains a function called periodically to store the stats in the DB.
  """
  alias DB.{AOM, Dataset, Region, Repo, StatsHistory}
  alias Geo.JSON
  alias Transport.CSVDocuments
  import Ecto.Query
  require Logger

  @doc """
  Compute and store all stats as a snapshot of the database
  """
  @spec store_stats() :: any()
  def store_stats do
    timestamp = DateTime.truncate(DateTime.utc_now(), :second)

    compute_stats() |> Enum.each(fn {k, v} -> store_stat_history(k, v, timestamp) end)
  end

  defp store_stat_history(key, values, %DateTime{} = timestamp)
       when key in [:gtfs_rt_types, :climate_resilience_bill_count, :count_geo_data_lines] do
    Enum.map(values, fn {type, count} ->
      store_stat_history("#{key}::#{type}", count, timestamp)
    end)
  end

  defp store_stat_history(key, value, %DateTime{} = timestamp) when is_number(value) do
    %StatsHistory{timestamp: timestamp, metric: to_string(key), value: value} |> Repo.insert!()
  end

  @doc """
  Compute all stats. Used both by the stats page and the periodic storage.
  """
  @spec compute_stats() :: any()
  def compute_stats do
    aoms =
      AOM
      |> join(:left, [a], d in assoc(a, :legal_owners_dataset), as: :legal_owners_dataset)
      |> join(:left, [a, legal_owners_dataset: legal_owners_dataset], d in Dataset,
        on: (d.id == legal_owners_dataset.id or d.aom_id == a.id) and d.is_active,
        as: :dataset
      )
      |> group_by([a], [a.id, a.population, a.region_id])
      |> select([a, dataset: d], %{
        population: a.population,
        region_id: a.region_id,
        nb_datasets: count(d.id)
      })
      |> Repo.all()

    aoms_with_datasets = aoms |> Enum.filter(&(&1.nb_datasets > 0))

    regions = Repo.all(from(r in Region, where: r.nom != "National"))

    aoms_max_gtfs_severity = compute_aom_gtfs_max_severity()

    total_aom_with_gtfs_datasets =
      aoms_max_gtfs_severity
      |> Map.values()
      |> Enum.filter(fn error -> not is_nil(error) end)
      |> Enum.sum()

    %{
      nb_datasets: Repo.aggregate(Dataset.base_query(), :count, :id),
      nb_pt_datasets: Dataset.count_by_type("public-transit"),
      nb_aoms: Enum.count(aoms),
      nb_aoms_with_data: Enum.count(aoms_with_datasets),
      nb_regions: Enum.count(regions),
      nb_regions_completed: regions |> Enum.count(fn r -> r.is_completed end),
      population_totale: get_population(aoms),
      population_couverte: get_population(aoms_with_datasets),
      ratio_aom_with_at_most_warnings:
        ratio_aom_with_at_most_warnings(aoms_max_gtfs_severity, total_aom_with_gtfs_datasets),
      ratio_aom_good_quality: ratio_aom_good_quality(aoms_max_gtfs_severity, total_aom_with_gtfs_datasets),
      aom_with_errors: Map.get(aoms_max_gtfs_severity, "Error", 0),
      aom_with_fatal: Map.get(aoms_max_gtfs_severity, "Fatal", 0),
      nb_official_public_transit_realtime: DB.Dataset.count_public_transport_has_realtime(),
      nb_reusers: nb_reusers(),
      nb_reuses: nb_reuses(),
      nb_dataset_types: nb_dataset_types(),
      nb_gtfs: count_dataset_with_format("GTFS"),
      nb_netex: count_dataset_with_format("NeTEx"),
      nb_bss_datasets: count_dataset_with_format("gbfs"),
      nb_bikes_scooter_datasets: DB.Dataset.count_by_type("bike-scooter-sharing"),
      nb_gtfs_rt: count_dataset_with_format("gtfs-rt"),
      gtfs_rt_types: count_feed_types_gtfs_rt(),
      climate_resilience_bill_count: count_datasets_climate_resilience_bill(),
      nb_siri: count_dataset_with_format("SIRI"),
      nb_siri_lite: count_dataset_with_format("SIRI Lite"),
      count_geo_data_lines: count_geo_data_lines()
    }
    |> Map.merge(gbfs_stats())
  end

  def gbfs_stats do
    today = Date.utc_today()

    # Latest metadata for each GBFS resource for today
    rows =
      DB.ResourceMetadata.base_query()
      |> join(:inner, [metadata: m], r in DB.Resource, on: r.id == m.resource_id, as: :resource)
      |> where([resource: r], r.format == "gbfs")
      |> where([metadata: m], fragment("?::date", m.inserted_at) == ^today and fragment("? \\? 'stats'", m.metadata))
      |> select([metadata: m], last_value(m.metadata) |> over(partition_by: m.resource_id, order_by: m.resource_id))
      |> distinct(true)
      |> DB.Repo.all()

    if Enum.empty?(rows) do
      %{}
    else
      [&gbfs_versions_stats/1, &gbfs_vehicle_types_stats/1, &gbfs_feed_types_stats/1, &gbfs_counters_stats/1]
      |> Enum.reduce(%{}, fn method, acc -> Map.merge(acc, method.(rows)) end)
    end
  end

  @doc """
  iex> gbfs_counters_stats([%{"stats" => %{"nb_stations" => 40, "nb_vehicles" => 5, "version" => 1}}, %{"stats" => %{"nb_stations" => 2, "nb_vehicles" => 3, "version" => 1}}])
  %{gbfs_nb_stations_sum: 42, gbfs_nb_vehicles_sum: 8}
  """
  def gbfs_counters_stats(rows) do
    rows
    # Keep only keys starting with `nb_`
    |> Enum.map(&Map.filter(&1["stats"], fn {k, _} -> String.starts_with?(k, "nb_") end))
    # Keep a single map, summing all values for each key
    |> Enum.reduce(&Map.merge(&1, &2, fn _, v1, v2 -> v1 + v2 end))
    |> Map.new(fn {k, v} -> {String.to_atom("gbfs_#{k}_sum"), v} end)
  end

  @doc """
  iex> gbfs_versions_stats([%{"versions" => ["3.0", "2.2"]}, %{"versions" => ["3.0", "1.0"]}])
  %{"gbfs_v1.0_count": 1, "gbfs_v2.2_count": 1, "gbfs_v3.0_count": 2}
  iex> gbfs_versions_stats([%{"versions" => nil}, %{"versions" => ["3.0", "1.0"]}])
  %{"gbfs_v1.0_count": 1, "gbfs_v3.0_count": 1}
  """
  def gbfs_versions_stats(rows) do
    rows
    |> Enum.flat_map(&(&1["versions"] || []))
    |> Enum.frequencies()
    |> Map.new(fn {k, v} -> {String.to_atom("gbfs_v#{k}_count"), v} end)
  end

  @doc """
  iex> gbfs_vehicle_types_stats([%{"vehicle_types" => ["bicycle", "scooter"]}, %{"vehicle_types" => ["bicycle"]}])
  %{gbfs_vehicle_type_bicycle_count: 2, gbfs_vehicle_type_scooter_count: 1}
  iex> gbfs_vehicle_types_stats([%{"vehicle_types" => ["bicycle"]}, %{"vehicle_types" => nil}])
  %{gbfs_vehicle_type_bicycle_count: 1}
  """
  def gbfs_vehicle_types_stats(rows) do
    rows
    |> Enum.flat_map(&(&1["vehicle_types"] || []))
    |> Enum.frequencies()
    |> Map.new(fn {k, v} -> {String.to_atom("gbfs_vehicle_type_#{k}_count"), v} end)
  end

  @doc """
  iex> gbfs_feed_types_stats([%{"types" => ["free_floating", "stations"]}, %{"types" => ["stations"]}])
  %{gbfs_feed_type_free_floating_count: 1, gbfs_feed_type_stations_count: 2}
  iex> gbfs_feed_types_stats([%{"types" => nil}, %{"types" => ["stations"]}])
  %{gbfs_feed_type_stations_count: 1}
  """
  def gbfs_feed_types_stats(rows) do
    rows
    |> Enum.flat_map(&(&1["types"] || []))
    |> Enum.frequencies()
    |> Map.new(fn {k, v} -> {String.to_atom("gbfs_feed_type_#{k}_count"), v} end)
  end

  @doc """
  Count the number of gtfs-rt entities seen in the last 7 days on our resources
  Output example: %{"service_alerts" => 12, "trip_updates" => 63, "vehicle_positions" => 42}
  """
  @spec count_feed_types_gtfs_rt :: map()
  def count_feed_types_gtfs_rt do
    features =
      DB.ResourceMetadata.base_query()
      |> distinct(true)
      |> join(:inner, [metadata: m], r in DB.Resource, on: r.id == m.resource_id, as: :resource)
      |> where(
        [metadata: m, resource: r],
        r.format == "gtfs-rt" and m.inserted_at > ^Transport.Jobs.GTFSRTMetadataJob.datetime_limit()
      )
      |> select([metadata: m], %{resource_id: m.resource_id, feature: fragment("unnest(?)", m.features)})

    q = from(f in subquery(features))

    q
    |> group_by([f], f.feature)
    |> select([f], {f.feature, count(f.feature)})
    |> DB.Repo.all()
    |> Enum.into(%{})
  end

  defp count_datasets_climate_resilience_bill do
    DB.Dataset.base_query()
    |> where([dataset: d], "loi-climat-resilience" in d.custom_tags)
    |> group_by([dataset: d], d.type)
    |> select([dataset: d], {d.type, count(d.id)})
    |> DB.Repo.all()
    |> Enum.into(%{})
  end

  defp get_population(datasets) do
    datasets
    |> Enum.reduce(0, &(&1.population + &2))
    |> Kernel./(1_000_000)
    |> Kernel.round()
  end

  defp nb_dataset_types do
    Dataset
    |> select([d], count(d.type, :distinct))
    |> Repo.one()
  end

  defp nb_reusers do
    Enum.count(CSVDocuments.reusers())
  end

  defp nb_reuses do
    Repo.aggregate(Dataset, :sum, :nb_reuses) || 0
  end

  def count_dataset_with_format(format) do
    Dataset.base_query()
    |> DB.Resource.join_dataset_with_resource()
    |> where([resource: r], r.format == ^format)
    |> select([resource: r], count(r.dataset_id, :distinct))
    |> Repo.one()
  end

  @spec compute_aom_gtfs_max_severity() :: %{binary() => integer()}
  def compute_aom_gtfs_max_severity do
    # consolidate the maximum error for the current datasets of each AOMs
    # return, for each error, the number of AOM with this maximum error
    dt = Date.utc_today()

    validation_infos =
      DB.Dataset.base_query()
      |> DB.Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
      |> select([resource: r, multi_validation: mv, metadata: m], %{
        max_error:
          fragment("""
          CASE max_error::text
          WHEN 'Fatal' THEN 4
          WHEN 'Error' THEN 3
          WHEN 'Warning' THEN 2
          WHEN 'Information' THEN 1
          ELSE 0
          END
          """),
        resource_id: r.id,
        end_date: fragment("TO_DATE(?->>'end_date', 'YYYY-MM-DD')", m.metadata)
      })

    AOM
    |> join(:left, [a], d in assoc(a, :legal_owners_dataset), as: :legal_owners_dataset)
    |> join(:left, [a, legal_owners_dataset: legal_owners_dataset], d in Dataset,
      on: (d.id == legal_owners_dataset.id or d.aom_id == a.id) and d.is_active,
      as: :dataset
    )
    |> join(:left, [_, _, dataset], _r in assoc(dataset, :resources))
    |> join(:left, [_, _, _, r], v in subquery(validation_infos), on: v.resource_id == r.id)
    |> where([_a, _l, _d, r, _v], r.format == "GTFS")
    |> where([_a, _l, _d, _r, v], v.end_date >= ^dt)
    |> group_by([a, _l, _d, _r, v], a.id)
    |> select([a, l, d, r, v], %{
      aom: a.id,
      max_error: max(v.max_error)
    })
    |> Repo.all()
    |> List.foldl(%{}, fn %{max_error: max_error}, acc ->
      max_error =
        case max_error do
          4 -> "Fatal"
          3 -> "Error"
          2 -> "Warning"
          1 -> "Information"
          0 -> "NoError"
          _ -> nil
        end

      Map.update(acc, max_error, 1, fn v -> v + 1 end)
    end)
  end

  @spec ratio_aom_with_at_most_warnings(%{binary() => integer()}, integer()) :: integer()
  defp ratio_aom_with_at_most_warnings(_aom_max_severity, 0) do
    0
  end

  defp ratio_aom_with_at_most_warnings(aom_max_severity, nb_aom_with_data) do
    sum =
      Map.get(aom_max_severity, "Warning", 0) +
        Map.get(aom_max_severity, "Information", 0) +
        Map.get(aom_max_severity, "Irrelevant", 0) +
        Map.get(aom_max_severity, "NoError", 0)

    sum / nb_aom_with_data
  end

  @spec ratio_aom_good_quality(%{binary() => integer()}, integer()) :: integer()
  defp ratio_aom_good_quality(_aom_max_severity, 0) do
    0
  end

  defp ratio_aom_good_quality(aom_max_severity, nb_aom_with_data) do
    sum =
      Map.get(aom_max_severity, "Information", 0) +
        Map.get(aom_max_severity, "Irrelevant", 0) +
        Map.get(aom_max_severity, "NoError", 0)

    sum / nb_aom_with_data
  end

  def count_geo_data_lines do
    Transport.ConsolidatedDataset.geo_data_datasets()
    |> Map.new(fn feature -> {feature, count_geo_data_lines(feature)} end)
  end

  def count_geo_data_lines(feature) do
    DB.Repo.get_by(DB.GeoDataImport, slug: feature)
    |> DB.GeoData.count_lines_for_geo_data_import()
  end

  # From now on the functions are used by the API stats controller

  @doc """
  Main entry point for the stats API controller.
  The result of this function is cached by the controller itself, see `TransportWeb.API.StatsController.render_features/3`.
  We directly return the final JSON structure to avoid re-encoding it.
  """
  def query_to_rendered_geojson(query) do
    query
    |> features()
    |> geojson()
    |> Jason.encode!()
  end

  def bike_scooter_sharing_rendered_geojson do
    bike_scooter_query()
    |> bike_scooter_sharing_features()
    |> geojson()
    |> Jason.encode!()
  end

  @spec features(Ecto.Query.t()) :: [map()]
  def features(q) do
    q
    |> Repo.all()
    |> Enum.reject(fn aom -> is_nil(aom.geometry) or new_aom_without_datasets?(aom) end)
    |> Enum.map(fn aom ->
      dataset_types =
        aom
        |> Map.get(:dataset_types, [])
        |> Enum.filter(fn {_, v} -> !is_nil(v) end)
        |> Enum.into(%{})

      %{
        "geometry" => aom.geometry |> JSON.encode!(),
        "type" => "Feature",
        "properties" => %{
          "dataset_count" => Map.get(aom, :nb_datasets, 0),
          "completed" => Map.get(aom, :is_completed, false),
          "nom" => Map.get(aom, :nom, ""),
          "id" => aom.id,
          "forme_juridique" => Map.get(aom, :forme_juridique, ""),
          "nb_other_datasets" => Map.get(aom, :nb_other_datasets, 0),
          "quality" => %{
            "expired_from" => %{
              # negative values are up to date datasets, we filter them
              "nb_days" => aom |> Map.get(:quality, %{}) |> Map.get(:expired_from) |> filter_neg,
              "status" =>
                case aom |> Map.get(:quality, %{}) |> Map.get(:expired_from) do
                  # if no validity period has been found, it's either that there was no data
                  # or that we were not able to read them
                  nil ->
                    case dataset_types[:pt] do
                      0 -> "no_data"
                      _ -> "unreadable"
                    end

                  i when i > 0 ->
                    "outdated"

                  _ ->
                    "up_to_date"
                end
            },
            "error_level" => aom |> Map.get(:quality, %{}) |> Map.get(:error_level)
          },
          "dataset_formats" =>
            aom
            |> Map.get(:dataset_formats, [])
            |> Enum.filter(fn {_, v} -> v != nil end)
            |> Enum.into(%{}),
          "dataset_types" => dataset_types
        }
      }
    end)
    |> Enum.to_list()
  end

  @spec bike_scooter_sharing_features(Ecto.Query.t()) :: [map()]
  def bike_scooter_sharing_features(query) do
    query
    |> DB.Repo.all()
    |> Enum.reject(fn r -> is_nil(r.geometry) end)
    |> Enum.map(fn r ->
      %{
        "geometry" => r.geometry |> JSON.encode!(),
        "type" => "Feature",
        # NOTE: there is a bug here - the key is an atom.
        # I won't change it now because it would mean more changes somewhere else, maybe.
        # `Map.reject(fn({k,v}) -> k == :geometry end)` will do it.
        "properties" => Map.take(r, Enum.filter(Map.keys(r), fn k -> k != "geometry" end))
      }
    end)
  end

  @spec geojson([map()]) :: map()
  def geojson(features),
    do: %{
      "type" => "FeatureCollection",
      # This is now completely incorrect!
      "name" => "Autorités organisatrices de Mobiltés",
      "features" => features
    }

  defmacro count_aom_types(aom_id, type, include_aggregates: true) do
    quote do
      fragment(
        """
        select count(d.id)
        from dataset d
        left join dataset_aom_legal_owner a on a.dataset_id = d.id and a.aom_id = ?
        where (d.aom_id = ? or a.dataset_id is not null) and d.is_active and d.type = ?
        """,
        unquote(aom_id),
        unquote(aom_id),
        unquote(type)
      )
    end
  end

  defmacro count_aom_types(aom_id, type) do
    quote do
      fragment(
        """
        select count(d.id)
        from dataset d
        where d.aom_id = ? and d.is_active and d.type = ?
        """,
        unquote(aom_id),
        unquote(type)
      )
    end
  end

  defmacro count_aom_format(aom_id, format) do
    quote do
      fragment(
        """
        SELECT COUNT(format)
        FROM resource
        WHERE format = ?
        AND dataset_id in (
          select d.id
          from dataset d
          left join dataset_aom_legal_owner a on a.dataset_id = d.id and a.aom_id = ?
          where (d.aom_id = ? or a.dataset_id is not null) and d.is_active
        )
        group by format
        """,
        unquote(format),
        unquote(aom_id),
        unquote(aom_id)
      )
    end
  end

  defmacro count_region_format(region, format) do
    quote do
      fragment(
        """
        SELECT COUNT(format) FROM resource
        JOIN dataset_geographic_view d_geo ON d_geo.dataset_id = resource.dataset_id
        WHERE d_geo.region_id = ?
        AND format = ? GROUP BY format
        """,
        unquote(region),
        unquote(format)
      )
    end
  end

  defmacro count_type_by_region(region_id, type) do
    quote do
      fragment(
        """
        SELECT COUNT(*) FROM dataset
        JOIN dataset_geographic_view d_geo ON d_geo.dataset_id = dataset.id
        WHERE d_geo.region_id = ? and is_active = TRUE
        AND type = ?
        """,
        unquote(region_id),
        unquote(type)
      )
    end
  end

  @spec aom_features_query :: Ecto.Query.t()
  def aom_features_query do
    nb_aggregates_dataset_by_aom =
      AOM
      |> join(:inner, [aom], d in assoc(aom, :legal_owners_dataset), as: :legal_owners_dataset)
      |> where(
        [legal_owners_dataset: d],
        d.id in subquery(
          Dataset.base_query()
          |> join(:inner, [dataset: d], aom in assoc(d, :legal_owners_aom), as: :aom)
          |> group_by([dataset: d], d.id)
          |> having([aom: a], count(a.id) >= 2)
          |> select([dataset: d], d.id)
        )
      )
      |> group_by([aom], aom.id)
      |> select([aom, legal_owners_dataset: d], %{aom_id: aom.id, count: count(d.id)})

    AOM
    |> join(:left, [aom], d in subquery(nb_aggregates_dataset_by_aom),
      on: aom.id == d.aom_id,
      as: :aggregates_by_aom
    )
    |> select([aom, aggregates_by_aom: d], %{
      geometry: aom.geom,
      id: aom.id,
      created_after_2021: aom.composition_res_id >= 1_000,
      insee_commune_principale: aom.insee_commune_principale,
      nb_datasets: fragment("select count(id) from dataset where aom_id = ? and is_active", aom.id),
      dataset_formats: %{
        gtfs: count_aom_format(aom.id, "GTFS"),
        netex: count_aom_format(aom.id, "NeTEx"),
        gtfs_rt: count_aom_format(aom.id, "gtfs-rt"),
        gbfs: count_aom_format(aom.id, "gbfs"),
        siri: count_aom_format(aom.id, "SIRI"),
        siri_lite: count_aom_format(aom.id, "SIRI Lite")
      },
      nom: aom.nom,
      forme_juridique: aom.forme_juridique,
      dataset_types: %{
        pt: count_aom_types(aom.id, "public-transit"),
        bike_scooter_sharing: count_aom_types(aom.id, "bike-scooter-sharing")
      },
      nb_other_datasets: coalesce(d.count, 0)
    })
  end

  @spec region_features_query :: Ecto.Query.t()
  def region_features_query do
    Region
    |> select([r], %{
      geometry: r.geom,
      id: r.id,
      nom: r.nom,
      is_completed: r.is_completed,
      nb_datasets:
        fragment(
          """
          SELECT COUNT(*) FROM dataset
          JOIN dataset_geographic_view d_geo ON d_geo.dataset_id = dataset.id
          WHERE d_geo.region_id = ?
          AND is_active=TRUE
          """,
          r.id
        ),
      dataset_formats: %{
        gtfs: count_region_format(r.id, "GTFS"),
        netex: count_region_format(r.id, "NeTEx"),
        gtfs_rt: count_region_format(r.id, "gtfs-rt"),
        gbfs: count_region_format(r.id, "gbfs"),
        siri: count_region_format(r.id, "SIRI"),
        siri_lite: count_region_format(r.id, "SIRI Lite")
      },
      dataset_types: %{
        pt: count_type_by_region(r.id, "public-transit"),
        bike_scooter_sharing: count_type_by_region(r.id, "bike-scooter-sharing")
      }
    })
  end

  @spec quality_features_query :: Ecto.Query.t()
  def quality_features_query do
    dt = Date.utc_today() |> Date.to_iso8601()

    error_info_sub = dataset_error_levels()
    expired_info_sub = dataset_expiration_dates()

    AOM
    |> join(:left, [a], d in assoc(a, :legal_owners_dataset), as: :legal_owners_dataset)
    |> join(:left, [a, legal_owners_dataset: legal_owners_dataset], d in Dataset,
      on: (d.id == legal_owners_dataset.id or d.aom_id == a.id) and d.is_active,
      as: :dataset
    )
    |> join(:left, [dataset: d], error_info in subquery(error_info_sub),
      on: error_info.dataset_id == d.id,
      as: :error_info
    )
    |> join(:left, [dataset: d], expired_info in subquery(expired_info_sub),
      on: expired_info.dataset_id == d.id,
      as: :expired_info
    )
    |> select(
      [aom, error_info: error_info, expired_info: expired_info],
      %{
        geometry: aom.geom,
        id: aom.id,
        created_after_2021: aom.composition_res_id >= 1_000,
        insee_commune_principale: aom.insee_commune_principale,
        nom: aom.nom,
        forme_juridique: aom.forme_juridique,
        dataset_types: %{
          pt: count_aom_types(aom.id, "public-transit", include_aggregates: true),
          bike_scooter_sharing: count_aom_types(aom.id, "bike-scooter-sharing", include_aggregates: true)
        },
        quality: %{
          expired_from: fragment("TO_DATE(?, 'YYYY-MM-DD') - max(?)", ^dt, expired_info.end_date),
          error_level: fragment("case max(CASE max_error::text
              WHEN 'Fatal' THEN 1
              WHEN 'Error' THEN 2
              WHEN 'Warning' THEN 3
              WHEN 'Information' THEN 4
              WHEN 'NoError' THEN 5
              END)
            WHEN 1 THEN 'Fatal'
            WHEN 2 THEN 'Error'
            WHEN 3 THEN 'Warning'
            WHEN 4 THEN 'Information'
            WHEN 5 THEN 'NoError'
          END
          ")
        }
      }
    )
    |> group_by([aom], aom.id)
  end

  @spec bike_scooter_query :: Ecto.Query.t()
  def bike_scooter_query do
    DB.DatasetGeographicView
    |> join(:left, [gv], dataset in Dataset, on: dataset.id == gv.dataset_id)
    |> select([gv, dataset], %{
      geometry: fragment("ST_Centroid(geom) as geometry"),
      names: fragment("array_agg(? order by ? asc)", dataset.custom_title, dataset.custom_title),
      slugs: fragment("array_agg(? order by ? asc)", dataset.slug, dataset.custom_title)
    })
    |> where([_gv, dataset], dataset.type == "bike-scooter-sharing" and dataset.is_active)
    |> group_by(fragment("geometry"))
  end

  def dataset_expiration_dates do
    DB.Dataset.base_query()
    |> DB.Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
    |> where([resource: r], r.is_available == true)
    |> select([dataset: d, metadata: m], %{
      dataset_id: d.id,
      end_date: fragment("TO_DATE(?->>'end_date', 'YYYY-MM-DD')", m.metadata)
    })
  end

  def dataset_error_levels do
    DB.Dataset.base_query()
    |> DB.Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
    |> DB.ResourceMetadata.where_gtfs_up_to_date()
    |> where([resource: r], r.is_available == true)
    |> select([dataset: d, multi_validation: mv], %{dataset_id: d.id, max_error: mv.max_error})
  end

  @spec filter_neg(nil | integer()) :: nil | non_neg_integer()
  defp filter_neg(nil), do: nil

  defp filter_neg(val) when val < 0, do: nil
  defp filter_neg(val) when val >= 0, do: val

  defp new_aom_without_datasets?(%{created_after_2021: true, nb_datasets: 0}), do: true
  defp new_aom_without_datasets?(%{created_after_2021: true, dataset_types: %{pt: 0}}), do: true
  defp new_aom_without_datasets?(_), do: false
end
