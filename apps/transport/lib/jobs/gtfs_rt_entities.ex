defmodule Transport.Jobs.GTFSRTMetadataDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `GTFSRTMetadataJob`.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query
  alias DB.{Dataset, Repo, Resource}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    relevant_resources()
    |> Enum.map(&(%{resource_id: &1.id} |> Transport.Jobs.GTFSRTMetadataJob.new()))
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
    count_entities |> Map.filter(fn {_, v} -> v > 0 end) |> Enum.map(fn {k, _} -> Atom.to_string(k) end)
  end

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
