defmodule Transport.Jobs.GTFSRTMetadataDispatcherJob do
  @moduledoc """
  Job in charge of:
  - removing old `DB.ResourceMetadata` for GTFS-RT resources
  - dispatching multiple `GTFSRTMetadataJob`.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query
  alias DB.{Repo, Resource, ResourceMetadata}

  @metadata_max_nb_days 90

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    relevant_resources()
    |> Enum.map(&(%{resource_id: &1.id} |> Transport.Jobs.GTFSRTMetadataJob.new()))
    |> Oban.insert_all()

    remove_old_metadata()

    :ok
  end

  def remove_old_metadata do
    recent_limit = DateTime.utc_now() |> DateTime.add(-@metadata_max_nb_days, :day)

    ResourceMetadata
    |> join(:inner, [rm], r in Resource, on: rm.resource_id == r.id and r.format == "gtfs-rt")
    |> where([rm, _r], rm.inserted_at < ^recent_limit)
    |> select([rm, _r], rm)
    |> Repo.delete_all()
  end

  def relevant_resources do
    DB.Dataset.base_query()
    |> DB.Resource.join_dataset_with_resource()
    |> where([resource: r], r.format == "gtfs-rt" and r.is_available)
    |> select([resource: r], r)
    |> Repo.all()
  end
end

defmodule Transport.Jobs.GTFSRTMetadataJob do
  @moduledoc """
  Job in charge of keeping track of which entities are present
  in a GTFS-RT feed.
  """
  use Oban.Worker, max_attempts: 3
  require Logger
  alias DB.{Repo, Resource}
  alias Transport.GTFSRT

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"resource_id" => id}}) do
    resource = Repo.get!(Resource, id)

    resource.url |> GTFSRT.decode_remote_feed() |> process_feed(resource)

    :ok
  end

  @doc """
  Identifies which entities are present in a feed from a count of entities.

  ## Examples

  iex> present_entities(%{})
  []
  iex> present_entities(%{service_alerts: 0, vehicle_positions: 1})
  ["vehicle_positions"]
  iex> present_entities(%{service_alerts: 2, vehicle_positions: 1})
  ["service_alerts", "vehicle_positions"]
  """
  def present_entities(count_entities) do
    count_entities
    |> Map.filter(fn {_, v} -> v > 0 end)
    |> Enum.map(fn {k, _} -> Atom.to_string(k) end)
    |> Enum.sort()
  end

  @spec process_feed({:error, any} | {:ok, TransitRealtime.FeedMessage.t()}, DB.Resource.t()) :: any
  def process_feed({:ok, %TransitRealtime.FeedMessage{} = feed}, %Resource{id: resource_id}) do
    count_entities = feed |> GTFSRT.count_entities()
    feed_timestamp_delay = %{feed_timestamp_delay: feed |> GTFSRT.feed_timestamp_delay()}
    metadata = Map.merge(count_entities, feed_timestamp_delay)

    %DB.ResourceMetadata{
      resource_id: resource_id,
      metadata: metadata,
      features: present_entities(count_entities)
    }
    |> Repo.insert!()
  end

  def process_feed({:error, _}, %Resource{id: id}) do
    Logger.error("Cannot decode GTFS-RT feed for resource##{id}")
  end

  def days_to_keep, do: 7

  def datetime_limit, do: DateTime.utc_now() |> DateTime.add(-days_to_keep() * 24 * 60 * 60)
end
