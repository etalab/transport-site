defmodule Transport.RealtimePoller do
  use GenServer
  require Logger

  @moduledoc """
  A first implementation of GenServer polling (GTFS-RT) realtime data
  only once per deployment, and broadcasting that to all connected clients.
  """

  def init(state) do
    # initial schedule is immediate, but via the same code path,
    # to ensure we jump on the data
    schedule_next_tick(0)

    {:ok, state}
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def schedule_next_tick(delay \\ 5_000) do
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
    process()
    {:noreply, state}
  end

  def process do
    task = fn {resource_id, resource_url} ->
      try do
        Logger.info("Processing #{resource_id}...")

        resource_id
        |> fetch_vehicle_positions_safely(resource_url)
        |> broadcast(resource_id)

        %{ok: true}
      rescue
        e -> %{error: e}
      end
    end

    relevant_resources()
    |> Task.async_stream(
      task,
      max_concurrency: 50,
      on_timeout: :kill_task,
      timeout: 10_000
    )
    |> Stream.run()
  end

  def broadcast(vehicle_positions, id) do
    TransportWeb.Endpoint.broadcast!("explore", "vehicle-positions", %{
      resource_id: id,
      vehicle_positions: vehicle_positions
    })
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
