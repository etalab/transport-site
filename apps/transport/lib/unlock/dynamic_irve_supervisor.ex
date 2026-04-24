defmodule Unlock.DynamicIRVESupervisor do
  use Supervisor
  require Logger

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Unlock.DynamicIRVE.FeedStore.create_table()

    children = [
      {DynamicSupervisor, name: Unlock.DynamicIRVE.FeedSupervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: Unlock.DynamicIRVE.AggregatorSupervisor, strategy: :one_for_one},
      {Unlock.DynamicIRVE.FeedStarter, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Reloads from scratch: terminates all running feed workers and aggregators,
  then starts one worker per feed and one aggregator per config item.
  Called at boot (via FeedStarter) and on config refresh (via backoffice).

  The brute-force approach avoids edge cases (same slug, changed URL;
  partial config drift) at the cost of a short gap where some feeds have
  no data — acceptable since the aggregator tolerates missing feeds.
  """
  def sync_feeds(config) do
    stop_all(Unlock.DynamicIRVE.AggregatorSupervisor)
    stop_all(Unlock.DynamicIRVE.FeedSupervisor)

    for item <- aggregate_items(config) do
      for feed <- item.feeds, do: start_feed(item.identifier, feed)
      start_aggregator(item)
    end
  end

  defp aggregate_items(config) do
    config
    |> Map.values()
    |> Enum.filter(&match?(%Unlock.Config.Item.DynamicIRVEAggregate{}, &1))
  end

  defp stop_all(supervisor) do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(supervisor) do
      DynamicSupervisor.terminate_child(supervisor, pid)
    end
  end

  defp start_feed(parent_id, feed) do
    Logger.info("[DynamicIRVE] Starting feed #{parent_id}/#{feed.slug}")

    DynamicSupervisor.start_child(
      Unlock.DynamicIRVE.FeedSupervisor,
      {Unlock.DynamicIRVE.FeedWorker, {parent_id, feed}}
    )
  end

  defp start_aggregator(item) do
    Logger.info("[DynamicIRVE] Starting aggregator #{item.identifier}")

    DynamicSupervisor.start_child(
      Unlock.DynamicIRVE.AggregatorSupervisor,
      {Unlock.DynamicIRVE.Aggregator, item}
    )
  end
end

defmodule Unlock.DynamicIRVE.FeedStarter do
  @moduledoc """
  Triggers sync_feeds once the DynamicSupervisors are ready.
  A Supervisor's init/1 cannot start dynamic children, so we use
  handle_continue to defer the call.
  """
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [])

  @impl true
  def init(_) do
    {:ok, nil, {:continue, :start_feeds}}
  end

  @impl true
  def handle_continue(:start_feeds, state) do
    # Skip boot-time sync in test env: the config fetcher Mox mock has no
    # default expectation, and tests that need the supervisor should call
    # sync_feeds/1 themselves with a stubbed config.
    unless Mix.env() == :test do
      config = Application.fetch_env!(:transport, :unlock_config_fetcher).fetch_config!()
      Unlock.DynamicIRVESupervisor.sync_feeds(config)
    end

    {:noreply, state}
  end
end
