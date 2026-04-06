defmodule Unlock.DynamicIRVE.FeedWorker do
  use GenServer
  require Logger

  def start_link(%Unlock.Config.Item.Generic.HTTP{} = feed) do
    GenServer.start_link(__MODULE__, feed, name: via(feed.slug))
  end

  def slug(pid), do: GenServer.call(pid, :slug)

  defp via(slug), do: {:via, Registry, {Unlock.DynamicIRVE.Registry, slug}}

  @impl true
  def init(feed) do
    Logger.info("[DynamicIRVE] Feed worker started: #{feed.slug} (#{feed.identifier})")
    schedule_tick()
    {:ok, feed}
  end

  @impl true
  def handle_call(:slug, _from, feed), do: {:reply, feed.slug, feed}

  @impl true
  def handle_info(:tick, feed) do
    schedule_tick()
    fetch_and_process(feed)
    {:noreply, feed}
  end

  # Catches HTTP errors and invalid CSV to avoid crashing the worker
  defp fetch_and_process(feed) do
    # decode_body: false keeps raw binary (Req still handles gzip decompression)
    case Req.get(feed.target_url, redirect_log_level: false, decode_body: false) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        # infer_schema_length: 0 → all columns as strings
        df = Explorer.DataFrame.load_csv!(body, infer_schema_length: 0)
        df = Explorer.DataFrame.select(df, expected_columns())
        Logger.info("[DynamicIRVE] #{feed.slug} => HTTP 200, #{Explorer.DataFrame.n_rows(df)} rows")
        Unlock.DynamicIRVE.FeedStore.put(feed.slug, %{df: df, last_updated_at: DateTime.utc_now(), error: nil})

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("[DynamicIRVE] #{feed.slug} => HTTP #{status}")
        put_error(feed.slug, "HTTP #{status}")

      {:error, reason} ->
        Logger.warning("[DynamicIRVE] #{feed.slug} => #{inspect(reason)}")
        put_error(feed.slug, inspect(reason))
    end
  rescue
    e ->
      Logger.warning("[DynamicIRVE] #{feed.slug} => #{Exception.message(e)}")
      put_error(feed.slug, Exception.message(e))
  end

  # Preserves existing df/last_updated_at, only sets the error fields
  defp put_error(slug, message) do
    previous = Unlock.DynamicIRVE.FeedStore.get(slug) || %{df: nil, last_updated_at: nil}
    Unlock.DynamicIRVE.FeedStore.put(slug, Map.merge(previous, %{error: message, last_errored_at: DateTime.utc_now()}))
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, tick_interval())
  end

  defp tick_interval, do: Application.fetch_env!(:transport, :dynamic_irve_tick_interval)

  defp expected_columns, do: Transport.IRVE.DynamicIRVESchema.build_schema_fields_list()
end
