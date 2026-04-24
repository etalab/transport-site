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
      %{id: :initial_sync, start: {Task, :start_link, [&initial_sync/0]}, restart: :transient}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Terminates all running feed workers, then starts one per feed across all
  `DynamicIRVEAggregate` config items. Called at boot and on backoffice reload.

  The brute-force approach avoids edge cases (renamed slug, changed URL, partial
  drift) at the cost of a short data gap — acceptable since consumers tolerate it.
  """
  def sync_feeds(config) do
    stop_all(Unlock.DynamicIRVE.FeedSupervisor)

    for item <- aggregate_items(config),
        feed <- item.feeds,
        do: start_feed(item.identifier, feed)
  end

  # Invoked once at boot via a transient Task child, after both DynamicSupervisors are up.
  defp initial_sync do
    # Skipped in :test so the config fetcher Mox mock needs no default expectation;
    # tests that need live feeds call sync_feeds/1 themselves with a stubbed config.
    unless Mix.env() == :test do
      config = Application.fetch_env!(:transport, :unlock_config_fetcher).fetch_config!()
      sync_feeds(config)
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
end
