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
      {Unlock.DynamicIRVE.FeedStarter, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Synchronizes running workers with the given config.
  Handles hot-reloading: stops workers removed from config,
  starts workers added to config, leaves existing ones untouched.
  Called at boot (via FeedStarter) and on config refresh (via backoffice).
  """
  def sync_feeds(config) do
    expected = expected_feeds(config)
    running = running_feed_slugs()
    stop_removed_feeds(expected, running)
    start_new_feeds(expected, running)
  end

  defp expected_feeds(config) do
    config
    |> Map.values()
    |> Enum.flat_map(fn
      %Unlock.Config.Item.DynamicIRVEAggregate{feeds: feeds} -> feeds
      _ -> []
    end)
  end

  defp stop_removed_feeds(expected, running) do
    expected_slugs = expected |> Enum.map(& &1.slug) |> MapSet.new()

    for slug <- running, slug not in expected_slugs do
      Logger.info("[DynamicIRVE] Stopping feed #{slug}")
      stop_feed(slug)
    end
  end

  defp start_new_feeds(expected, running) do
    for feed <- expected, feed.slug not in running do
      Logger.info("[DynamicIRVE] Starting feed #{feed.slug}")
      DynamicSupervisor.start_child(
        Unlock.DynamicIRVE.FeedSupervisor,
        {Unlock.DynamicIRVE.FeedWorker, feed}
      )
    end
  end

  defp running_feed_slugs do
    DynamicSupervisor.which_children(Unlock.DynamicIRVE.FeedSupervisor)
    |> Enum.map(fn {_, pid, _, _} -> Unlock.DynamicIRVE.FeedWorker.slug(pid) end)
    |> MapSet.new()
  end

  defp stop_feed(slug) do
    case Registry.lookup(Unlock.DynamicIRVE.Registry, slug) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Unlock.DynamicIRVE.FeedSupervisor, pid)
      [] -> :ok
    end
  end
end

defmodule Unlock.DynamicIRVE.FeedStarter do
  @moduledoc """
  Triggers sync_feeds once the DynamicSupervisor is ready.
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
    config = Application.fetch_env!(:transport, :unlock_config_fetcher).fetch_config!()
    Unlock.DynamicIRVESupervisor.sync_feeds(config)
    {:noreply, state}
  end
end
