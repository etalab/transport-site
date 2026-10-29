defmodule Unlock.DynamicIRVESupervisor do
  @moduledoc """
  Root supervisor for the dynamic IRVE pipeline: owns the feed workers and
  their ETS-backed store.

  Call `sync_feeds/0` to align running workers with the latest proxy config —
  invoked once at boot and on the backoffice "refresh proxy config" action.
  """

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
      # Calls `sync_feeds/0` once at boot in a separate short-lived process: fetches
      # the config (HTTP to GitHub) and (re)starts one poller per feed in the
      # DynamicSupervisor above.
      # `sync_feeds/0` may raise (HTTP to GitHub) — let it crash: `:temporary` → a failure
      # is not restarted and does not affect sibling boot, and the stack trace bubbles up to Sentry.
      {Task, &sync_feeds/0}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Fetches the current proxy config, terminates all running feed workers, then
  starts one per feed across all `DynamicIRVEAggregate` items. Called at boot
  and on backoffice reload. No-op when polling is disabled (everywhere but
  production webserver nodes, see `config/runtime.exs`).

  The brute-force approach avoids edge cases (renamed slug, changed URL, partial
  drift) at the cost of a short data gap — acceptable for now.
  """
  def sync_feeds do
    if Application.fetch_env!(:transport, :dynamic_irve_polling_enabled) do
      config = Application.fetch_env!(:transport, :unlock_config_fetcher).fetch_config!()

      stop_all(Unlock.DynamicIRVE.FeedSupervisor)

      for item <- Map.values(config),
          match?(%Unlock.Config.Item.DynamicIRVEAggregate{}, item),
          feed <- item.feeds,
          do: start_feed(item.identifier, feed)
    else
      Logger.info("[DynamicIRVE] Polling disabled, not starting feed workers")
    end
  end

  @doc """
  Lists the currently running feed pollers as `{parent_id, slug}` tuples,
  read from `Unlock.DynamicIRVE.Registry`. Useful for tests and the debug LiveView.
  """
  def running_feed_pollers do
    # ETS match spec: each Registry entry is `{key, pid, value}`. We bind the key
    # to `:"$1"` (a positional capture, like a numbered placeholder) and ignore the
    # rest with `:_`. The body `[:"$1"]` says "return only what we captured".
    # Equivalent to `for {key, _pid, _value} <- entries, do: key`, but executed
    # inside ETS without copying the table.
    # See https://hexdocs.pm/elixir/Registry.html#select/2
    Registry.select(Unlock.DynamicIRVE.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
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
