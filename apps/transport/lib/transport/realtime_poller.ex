defmodule Transport.RealtimePoller do
  use GenServer
  require Logger

  def init(state) do
    # initial schedule is immediate, but via the same code path,
    # to ensure we jump on the data
    schedule_next_tick(0)
    resource_id = 67732
    {:ok, state
      |> Map.put(:resource_id, resource_id)
      |> Map.put(:url, DB.Repo.get!(DB.Resource, resource_id).url)
    }
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def schedule_next_tick(delay \\ 5_000) do
    Process.send_after(self(), :tick, delay)
  end

  def handle_info(:tick, state) do
    schedule_next_tick()
    # Hardcoded resource with vehicle positions for now
    fetch_vehicle_positions_safely(state.url)
    |> broadcast(state[:resource_id])
    {:noreply, state}
  end

  def broadcast(vehicle_positions, id) do
    TransportWeb.Endpoint.broadcast!("explore", "vehicle-positions", %{
      resource_id: id,
      vehicle_positions: vehicle_positions
    })
  end

  def fetch_vehicle_positions_safely(url) do
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
      "Timestamp is #{timestamp} aka #{timestamp |> DateTime.from_unix!()}, while query time is #{query_time}"
    )

    # NOTE: we cannot directly use Protobuf.JSON.encode!() because
    # this currently requires protobuf3 and some feeds are protobuf2
    entity
    |> Enum.filter(& &1.vehicle)
    |> Enum.map(& &1.vehicle)
    |> Enum.map(fn v ->
      %{
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
        # TODO: some trip are empty, causing a nil exception, so we'll need to verify the presence
        # trip: %{
        #   trip_id: v.trip.trip_id,
        # }
      }
    end)
  rescue
    e ->
      Logger.error(e)
      # TODO: propagate error instead of this
      []
  end
end
