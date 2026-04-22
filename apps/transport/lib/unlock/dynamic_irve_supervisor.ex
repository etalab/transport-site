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
      {Unlock.DynamicIRVE.FeedStarter, []},
      Unlock.DynamicIRVE.Aggregator
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Reloads workers from scratch: terminates all running feed workers,
  then starts one per feed in the config. Called at boot (via FeedStarter)
  and on config refresh (via backoffice).

  The brute-force approach avoids edge cases (same slug, changed URL;
  partial config drift) at the cost of a short gap where some feeds have
  no data — acceptable since the aggregator tolerates missing feeds.
  """
  def sync_feeds(config) do
    stop_feeds()
    start_feeds(expected_feeds(config))
  end

  defp expected_feeds(config) do
    config
    |> Map.values()
    |> Enum.flat_map(fn
      %Unlock.Config.Item.DynamicIRVEAggregate{feeds: feeds} -> feeds
      _ -> []
    end)
  end

  defp stop_feeds do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(Unlock.DynamicIRVE.FeedSupervisor) do
      Logger.info("[DynamicIRVE] Stopping feed #{Unlock.DynamicIRVE.FeedWorker.slug(pid)}")
      DynamicSupervisor.terminate_child(Unlock.DynamicIRVE.FeedSupervisor, pid)
    end
  end

  defp start_feeds(feeds) do
    for feed <- feeds do
      Logger.info("[DynamicIRVE] Starting feed #{feed.slug}")

      DynamicSupervisor.start_child(
        Unlock.DynamicIRVE.FeedSupervisor,
        {Unlock.DynamicIRVE.FeedWorker, feed}
      )
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
