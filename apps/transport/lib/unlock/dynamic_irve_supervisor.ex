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
      # Unique-keys registry: guarantees at most one worker per (parent_id, slug),
      # even under concurrent sync_feeds calls (e.g. boot Task + backoffice refresh).
      {Registry, keys: :unique, name: Unlock.DynamicIRVE.Registry},
      {DynamicSupervisor, name: Unlock.DynamicIRVE.FeedSupervisor, strategy: :one_for_one},
      {Task, &initial_sync/0}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Fetches the current proxy config, terminates all running feed workers, then
  starts one per feed across all `DynamicIRVEAggregate` items. Called at boot
  and on backoffice reload.

  The brute-force approach avoids edge cases (renamed slug, changed URL, partial
  drift) at the cost of a short data gap — acceptable since consumers tolerate it.
  """
  def sync_feeds do
    config = Application.fetch_env!(:transport, :unlock_config_fetcher).fetch_config!()

    stop_all(Unlock.DynamicIRVE.FeedSupervisor)

    for item <- Map.values(config),
        match?(%Unlock.Config.Item.DynamicIRVEAggregate{}, item),
        feed <- item.feeds,
        do: start_feed(item.identifier, feed)
  end

  # Invoked once at boot via a transient Task child, after the DynamicSupervisor is up.
  # Skipped in :test so the config fetcher Mox mock needs no default expectation;
  # tests that want workers running set their own expectation and call sync_feeds/0.
  defp initial_sync, do: unless(Mix.env() == :test, do: sync_feeds())

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
end
