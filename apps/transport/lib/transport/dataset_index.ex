defmodule Transport.DatasetIndex do
  @moduledoc """
  A GenServer that builds and maintains an in-memory index of datasets.

  Used for filtering, sorting and computing facets (type, licence, real-time,
  region, resource formats, subtypes, modes, offers) without hitting the database.

  The index is refreshed every 30 minutes.
  """
  use GenServer
  import Ecto.Query

  @refresh_interval :timer.minutes(30)

  @licences_ouvertes ~w(fr-lo lov2)
  @param_filter_keys ~w(type subtype licence filter format region custom_tag organization_id modes identifiant_offre)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @spec get :: map()
  def get do
    GenServer.call(__MODULE__, :get)
  end

  @impl true
  def init(state) do
    schedule_refresh(0)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, _state) do
    state = build_index()
    schedule_refresh()
    {:noreply, state}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:refresh, _from, _state) do
    state = build_index()
    {:reply, :ok, state}
  end

  @doc """
  Force a synchronous refresh of the index. Useful for tests.
  """
  @spec refresh :: :ok
  def refresh do
    GenServer.call(__MODULE__, :refresh)
  end

  defp schedule_refresh(delay \\ @refresh_interval) do
    Process.send_after(self(), :tick, delay)
  end

  # --- Facet computation ---

  @doc """
  Compute subtypes facet counts from the index for the given dataset IDs,
  filtered to entries matching `parent_type`.

  Returns `%{all: total, subtypes: [%{subtype: slug, count: count, msg: label}]}`.
  `all` is the number of datasets matching `parent_type` (not the sum of per-subtype counts,
  since a dataset can have multiple subtypes).
  """
  @spec subtypes(map(), [integer()], binary()) :: %{
          all: non_neg_integer(),
          subtypes: [%{subtype: binary(), count: non_neg_integer(), msg: binary()}]
        }
  def subtypes(index, dataset_ids, parent_type) do
    entries =
      index
      |> entries_for(dataset_ids)
      |> Enum.filter(&(&1.type == parent_type))

    subtypes =
      entries
      |> Enum.flat_map(& &1.subtypes)
      |> Enum.frequencies()
      |> Enum.map(fn {slug, count} -> %{subtype: slug, count: count, msg: DB.Dataset.subtype_to_str(slug)} end)

    %{all: length(entries), subtypes: subtypes}
  end

  @doc """
  Compute type facet counts from the index for the given dataset IDs.

  Returns a list of `%{type: type, count: count}` maps.
  """
  @spec types(map(), [integer()]) :: [%{type: binary(), count: non_neg_integer(), msg: binary()}]
  def types(index, dataset_ids) do
    index
    |> entries_for(dataset_ids)
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, entries} -> %{type: type, count: length(entries), msg: DB.Dataset.type_to_str(type)} end)
  end

  @doc """
  Compute licence facet counts from the index for the given dataset IDs.

  Groups `fr-lo` and `lov2` into `licence-ouverte`.
  Returns a list of `%{licence: licence, count: count}` maps, with `licence-ouverte` first.
  """
  @spec licences(map(), [integer()]) :: [%{licence: binary(), count: non_neg_integer()}]
  def licences(index, dataset_ids) do
    index
    |> entries_for(dataset_ids)
    |> Enum.group_by(&normalize_licence(&1.licence))
    |> Enum.map(fn {licence, entries} -> %{licence: licence, count: length(entries)} end)
    |> Enum.sort_by(&Map.get(%{"licence-ouverte" => 1}, &1.licence, 0), :desc)
  end

  @doc """
  Compute real-time facet counts from the index for the given dataset IDs.

  Returns `%{all: total_count, true: realtime_count}`.
  """
  @spec realtime_count(map(), [integer()]) :: %{all: non_neg_integer(), true: non_neg_integer()}
  def realtime_count(index, dataset_ids) do
    entries = entries_for(index, dataset_ids)

    %{
      all: length(entries),
      true: Enum.count(entries, & &1.has_realtime)
    }
  end

  @doc """
  Compute resource format facet counts from the index for the given dataset IDs.

  Returns a keyword list sorted by count (descending), with an `:all` key for the total
  number of datasets that have at least one format.
  """
  @spec resource_format_count(map(), [integer()]) :: [{atom() | binary(), non_neg_integer()}]
  def resource_format_count(index, dataset_ids) do
    entries = entries_for(index, dataset_ids)

    format_counts =
      entries
      |> Enum.flat_map(& &1.formats)
      |> Enum.frequencies()

    %{all: Enum.count(entries, &(&1.formats != []))}
    |> Map.merge(format_counts)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
  end

  @doc """
  Compute region facet counts from the index for the given dataset IDs.

  Returns a list of `%{nom: name, insee: insee, count: count}` maps ordered by name.
  Includes all regions (even those with count 0).
  """
  @spec regions(map(), [integer()]) :: [%{nom: binary(), insee: binary(), count: non_neg_integer()}]
  def regions(index, dataset_ids) do
    region_counts =
      index
      |> entries_for(dataset_ids)
      |> Enum.reject(&is_nil(&1.region_id))
      |> Enum.group_by(&{&1.region_id, &1.region_name, &1.region_insee})
      |> Map.new(fn {{id, _name, _insee}, entries} -> {id, length(entries)} end)

    all_regions()
    |> Enum.map(fn %{id: id, nom: nom, insee: insee} ->
      %{nom: nom, insee: insee, count: Map.get(region_counts, id, 0)}
    end)
    |> Enum.sort_by(& &1.nom)
  end

  # --- Filtering ---

  @doc """
  Filter dataset IDs from the index based on the given params.

  Supported filters: type, subtype, licence, filter (has_realtime), format,
  region, custom_tag, organization_id, modes, identifiant_offre.
  """
  @spec filter_dataset_ids(map(), map()) :: [integer()]
  def filter_dataset_ids(index, params) do
    # Pre-select only the filter keys whose param is present and non-empty,
    # so we don't check every filter for every entry.
    active_filters =
      for key <- @param_filter_keys,
          (val = Map.get(params, key)) not in [nil, ""],
          do: {key, val}

    index
    |> Enum.filter(fn {_id, entry} ->
      Enum.all?(active_filters, fn {key, val} -> match_param?(key, entry, val) end)
    end)
    |> Enum.map(fn {id, _entry} -> id end)
  end

  defp match_param?("type", entry, type), do: entry.type == type
  defp match_param?("subtype", entry, subtype), do: subtype in entry.subtypes

  defp match_param?("licence", entry, "licence-ouverte"), do: entry.licence in @licences_ouvertes
  defp match_param?("licence", entry, licence), do: entry.licence == licence

  defp match_param?("filter", entry, "has_realtime"), do: entry.has_realtime
  defp match_param?("filter", _entry, _other), do: true

  defp match_param?("format", entry, format), do: format in entry.formats
  defp match_param?("region", entry, region), do: entry.region_insee == region
  defp match_param?("custom_tag", entry, tag), do: tag in entry.custom_tags
  defp match_param?("organization_id", entry, org_id), do: to_string(entry.organization_id) == to_string(org_id)

  defp match_param?("modes", _entry, modes) when not is_list(modes) or modes == [], do: true
  defp match_param?("modes", entry, modes), do: Enum.all?(modes, &(&1 in entry.modes))

  defp match_param?("identifiant_offre", entry, id) do
    parsed = if is_binary(id), do: String.to_integer(id), else: id
    parsed in entry.offer_ids
  end

  # --- Sorting ---

  @doc """
  Sort dataset IDs in memory based on the given params.

  - `order_by=alpha`: sort by custom_title ASC
  - `order_by=most_recent`: sort by inserted_at DESC (nulls last)
  - No `q` param: sort by "base nationale" priority, then population DESC, then custom_title ASC
  - With `q` param: no in-memory sort (fulltext ranking stays in DB)
  """
  @spec order_dataset_ids([integer()], map(), map()) :: [integer()]
  def order_dataset_ids(dataset_ids, index, %{"order_by" => "alpha"}) do
    Enum.sort_by(dataset_ids, fn id -> (index[id].custom_title || "") |> String.downcase() end)
  end

  def order_dataset_ids(dataset_ids, index, %{"order_by" => "most_recent"}) do
    Enum.sort_by(
      dataset_ids,
      fn id ->
        case index[id].inserted_at do
          nil -> {0, nil}
          dt -> {1, DateTime.to_iso8601(dt)}
        end
      end,
      :desc
    )
  end

  def order_dataset_ids(dataset_ids, _index, %{"q" => _q}), do: dataset_ids

  def order_dataset_ids(dataset_ids, index, _params) do
    pan_publisher = Application.fetch_env!(:transport, :datagouvfr_transport_publisher_id)

    Enum.sort_by(dataset_ids, fn id -> default_sort_key(index[id], pan_publisher) end)
  end

  defp default_sort_key(entry, pan_publisher) do
    base_nationale =
      if to_string(entry.organization_id) == pan_publisher and
           is_binary(entry.custom_title) and
           entry.custom_title |> String.downcase() |> String.starts_with?("base nationale") do
        0
      else
        1
      end

    {base_nationale, -(entry.population || 0), (entry.custom_title || "") |> String.downcase()}
  end

  # --- Index building ---

  @doc false
  @spec build_index :: map()
  def build_index do
    datasets =
      DB.Dataset.base_query()
      |> DB.Dataset.reject_archived_datasets()
      |> preload([:resources, :dataset_subtypes, :offers])
      |> DB.Repo.all()

    region_mapping = build_region_mapping()

    Map.new(datasets, fn dataset -> {dataset.id, build_entry(dataset, region_mapping)} end)
  end

  defp build_entry(dataset, region_mapping) do
    region = Map.get(region_mapping, dataset.id)

    %{
      type: dataset.type,
      licence: dataset.licence,
      has_realtime: dataset.has_realtime,
      region_id: if(region, do: region.id),
      region_name: if(region, do: region.nom),
      region_insee: if(region, do: region.insee),
      formats: DB.Dataset.formats(dataset),
      subtypes: Enum.map(dataset.dataset_subtypes, & &1.slug),
      custom_tags: dataset.custom_tags || [],
      organization_id: dataset.organization_id,
      population: dataset.population,
      custom_title: dataset.custom_title,
      inserted_at: dataset.inserted_at,
      datagouv_title: dataset.datagouv_title,
      modes: extract_modes(dataset),
      offer_ids: Enum.map(dataset.offers, & &1.identifiant_offre)
    }
  end

  defp extract_modes(%DB.Dataset{} = dataset) do
    dataset
    |> DB.Dataset.official_resources()
    |> Enum.flat_map(fn r -> get_in(r, [Access.key(:counter_cache), Access.key("gtfs_modes")]) || [] end)
    |> Enum.uniq()
  end

  # --- Helpers ---

  defp all_regions do
    DB.Region
    |> select([r], %{id: r.id, nom: r.nom, insee: r.insee})
    |> DB.Repo.all()
  end

  defp entries_for(index, dataset_ids) do
    index |> Map.take(dataset_ids) |> Map.values()
  end

  defp normalize_licence(licence) do
    if licence in @licences_ouvertes, do: "licence-ouverte", else: licence
  end

  @spec build_region_mapping :: map()
  defp build_region_mapping do
    DB.DatasetGeographicView
    |> join(:inner, [dgv], r in DB.Region, on: dgv.region_id == r.id)
    |> select([dgv, r], {dgv.dataset_id, %{id: r.id, nom: r.nom, insee: r.insee}})
    |> DB.Repo.all()
    |> Map.new()
  end
end
