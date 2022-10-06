defmodule Transport.Jobs.GTFSRTEntitiesDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `GTFSRTEntitiesJob`.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query
  alias DB.{Dataset, Repo, Resource}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    relevant_resources()
    |> Enum.map(&(%{resource_id: &1.id} |> Transport.Jobs.GTFSRTEntitiesJob.new()))
    |> Oban.insert_all()

    :ok
  end

  def relevant_resources do
    Resource
    |> join(:inner, [r], d in Dataset, on: r.dataset_id == d.id)
    |> where([_r, d], d.is_active)
    |> where([r, _d], r.format == "gtfs-rt" and r.is_available)
    |> Repo.all()
  end
end

defmodule Transport.Jobs.GTFSRTEntitiesJob do
  @moduledoc """
  Job in charge of keeping track of which entities are present
  in a GTFS-RT feed over the last 7 days by leveraging what has
  been seen and stored in the metadata and decoding
  the feed when the job is performed.
  """
  use Oban.Worker, max_attempts: 3
  require Logger
  alias DB.{Repo, Resource}
  alias Transport.GTFSRT

  @entities_metadata_key "entities_last_seen"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"resource_id" => id}}) do
    resource = Repo.get!(Resource, id)

    resource.url |> GTFSRT.decode_remote_feed() |> process_feed(resource)

    :ok
  end

  defp present_entities(count_entities) do
    count_entities |> Map.filter(fn {_, v} -> v > 0 end) |> Enum.map(fn {k, _} -> Atom.to_string(k) end)
  end

  def process_feed({:ok, feed}, %Resource{metadata: metadata} = resource) do
    metadata = metadata || %{}
    count_entities = feed |> GTFSRT.count_entities()

    # this will be deleted later
    # ⬇️⬇️⬇️
    new_entities =
      compute_new_entities(
        Map.get(metadata, @entities_metadata_key, %{}),
        count_entities,
        DateTime.utc_now()
      )

    resource
    |> Resource.changeset(%{
      metadata: Map.put(metadata, @entities_metadata_key, new_entities),
      features: Map.keys(new_entities)
    })
    |> Repo.update!()

    # ⬆️⬆️⬆️

    %DB.ResourceMetadata{
      resource_id: resource.id,
      metadata: count_entities,
      features: present_entities(count_entities)
    }
    |> Repo.insert!()
  end

  def process_feed({:error, _}, %Resource{id: id}) do
    Logger.error("Cannot decode GTFS-RT feed for resource##{id}")
  end

  @doc """
  Compute entities that have been seen in the feed over the last
  `days_to_keep()` days, using:
  - existing_entities: `%{"trip_updates" => "2022-03-18 15:43:40.963443Z", "vehicle_positions" => "2022-03-18 15:43:40.963443Z"}`
  - entities_in_feed: `%{trip_updates: 4, vehicle_positions: 0, service_alerts: 0}`

  Will return the same type as `existing_entities`.
  """
  def compute_new_entities(existing_entities, entities_in_feed, now) do
    entities_present = present_entities(entities_in_feed)

    entities_still_valid =
      existing_entities
      |> Map.filter(fn {_, v} ->
        {:ok, dt, 0} = DateTime.from_iso8601(v)
        period_start = DateTime.add(now, -1 * 60 * 60 * 24 * days_to_keep(), :second)
        DateTime.compare(dt, period_start) == :gt
      end)

    Map.merge(entities_still_valid, entities_present |> Enum.into(%{}, &{&1, now |> DateTime.to_string()}))
  end

  def days_to_keep, do: 7
end
