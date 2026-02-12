defmodule Transport.DatasetIndex do
  @moduledoc """
  A GenServer that builds and maintains an in-memory index of dataset facets
  (type, licence, real-time, region, resource formats).

  The index is refreshed every 30 minutes.
  """
  use GenServer
  import Ecto.Query

  @refresh_interval :timer.minutes(30)

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

  defp all_regions do
    DB.Region
    |> select([r], %{id: r.id, nom: r.nom, insee: r.insee})
    |> DB.Repo.all()
  end

  defp entries_for(index, dataset_ids) do
    index |> Map.take(dataset_ids) |> Map.values()
  end

  defp normalize_licence(licence) when licence in ~w(fr-lo lov2), do: "licence-ouverte"
  defp normalize_licence(licence), do: licence

  @doc false
  @spec build_index :: map()
  def build_index do
    datasets =
      DB.Dataset.base_query()
      |> preload([:resources, :dataset_subtypes])
      |> DB.Repo.all()

    region_mapping = build_region_mapping()

    Map.new(datasets, fn dataset ->
      region = Map.get(region_mapping, dataset.id)

      {dataset.id,
       %{
         type: dataset.type,
         licence: dataset.licence,
         has_realtime: dataset.has_realtime,
         region_id: if(region, do: region.id),
         region_name: if(region, do: region.nom),
         region_insee: if(region, do: region.insee),
         formats: DB.Dataset.formats(dataset),
         subtypes: Enum.map(dataset.dataset_subtypes, & &1.slug)
       }}
    end)
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
