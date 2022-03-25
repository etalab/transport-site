defmodule Transport.RealtimePoller do
  use GenServer
  require Logger

  @moduledoc """
  A system to poll all active GTFS-RT feeds in the database, and broadcast
  the data via pubsub to the subscribed clients.
  """

  # NOTE: at time of writing, the code will not result into `:tick` events stacking
  # up in the mailbox, because the code is synchronously waiting for all requests to finish.
  # if going asynchronous, though, it will be important to flush multiple `:tick` messages,
  # to avoid overload.
  @tick_frequency 5_000
  @http_timeout 10_000

  def init(state) do
    # initial schedule is immediate, but via the same code path,
    # to ensure we jump on the data
    schedule_next_tick(0)

    {:ok, state}
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def schedule_next_tick(delay \\ @tick_frequency) do
    Process.send_after(self(), :tick, delay)
  end

  import Ecto.Query

  # separated here so that we can filter if we want
  def relevant_resources do
    DB.Resource
    |> where(format: "gtfs-rt")
    |> preload(:dataset)
    |> DB.Repo.all()
    |> Enum.filter(& &1.dataset.is_active)
    |> Enum.map(&{&1.id, &1.url})
  end

  def handle_info(:tick, state) do
    schedule_next_tick()
    count = viewers_count()

    if count > 0 do
      Logger.info("Processing (#{count} viewers connected)")
      process()
    end

    {:noreply, state}
  end

  def viewers do
    TransportWeb.Presence
    |> Phoenix.Presence.list(TransportWeb.ExploreChannel.explore_topic())
    |> get_in([TransportWeb.ExploreChannel.viewers_key(), :metas])
  end

  def viewers_count do
    case viewers() do
      nil -> 0
      list when is_list(list) -> list |> length()
    end
  end

  def process do
    task = fn {resource_id, resource_url} ->
      Logger.info("Processing #{resource_id}...")

      outcome =
        try do
          positions =
            resource_id
            |> fetch_vehicle_positions_safely(resource_url)

          %{vehicle_positions: positions}
        rescue
          # NOTE: out of precaution, I'm not forwarding the full exception to the client at the moment
          e ->
            Logger.error(e)
            %{error: true}
        end

      %{resource_id: resource_id}
      |> Map.merge(outcome)
      |> broadcast()
    end

    relevant_resources()
    |> Task.async_stream(
      task,
      max_concurrency: 50,
      on_timeout: :kill_task,
      timeout: @http_timeout
    )
    |> Stream.run()
  end

  def broadcast(payload) do
    TransportWeb.ExploreChannel.explore_topic()
    |> TransportWeb.Endpoint.broadcast!("vehicle-positions", payload)
  end

  def fetch_vehicle_positions_safely(resource_id, url) do
    query_time = DateTime.utc_now()
    %{status_code: 200, body: body} = Transport.Shared.Wrapper.HTTPoison.impl().get!(url, [], follow_redirect: true)

    %{
      header: %{
        gtfs_realtime_version: _version,
        incrementality: :FULL_DATASET,
        timestamp: timestamp
      },
      entity: entity
    } = TransitRealtime.FeedMessage.decode(body)

    Logger.info(
      "resource:#{resource_id} - timestamp=#{timestamp} #{timestamp |> DateTime.from_unix!()} query_time=#{query_time}"
    )

    # NOTE: we cannot directly use Protobuf.JSON.encode!() because
    # this currently requires protobuf3 and some feeds are protobuf2
    entity
    |> Enum.filter(& &1.vehicle)
    |> Enum.map(& &1.vehicle)
    |> Enum.map(fn v ->
      %{
        transport: %{
          resource_id: resource_id
        },
        vehicle: %{
          id: v.vehicle.id
        },
        position: %{
          latitude: v.position.latitude,
          longitude: v.position.longitude,
          bearing: v.position.bearing,
          odometer: v.position.odometer,
          speed: v.position.speed
        }
        # NOTE: some trip are empty, causing a nil exception, so we'll need to verify the presence
        # trip: %{
        #   trip_id: v.trip.trip_id,
        # }
      }
    end)
  end
end
