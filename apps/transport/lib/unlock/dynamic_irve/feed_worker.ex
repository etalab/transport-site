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
    fetch_and_process(feed)
    schedule_tick()
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
        n_rows = Explorer.DataFrame.n_rows(df)
        n_unique = df["id_pdc_itinerance"] |> Explorer.Series.distinct() |> Explorer.Series.count()
        Logger.info("[DynamicIRVE] #{feed.slug} => HTTP 200, #{n_rows} rows, #{n_unique} unique id_pdc")
        Unlock.DynamicIRVE.FeedStore.put(feed.slug, %{df: df, updated_at: DateTime.utc_now(), error: nil})

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("[DynamicIRVE] #{feed.slug} => HTTP #{status}")
        Unlock.DynamicIRVE.FeedStore.put(feed.slug, %{df: nil, updated_at: nil, error: "HTTP #{status}"})

      {:error, reason} ->
        Logger.warning("[DynamicIRVE] #{feed.slug} => #{inspect(reason)}")
        Unlock.DynamicIRVE.FeedStore.put(feed.slug, %{df: nil, updated_at: nil, error: inspect(reason)})
    end
  rescue
    e ->
      Logger.warning("[DynamicIRVE] #{feed.slug} => #{Exception.message(e)}")
      Unlock.DynamicIRVE.FeedStore.put(feed.slug, %{df: nil, updated_at: nil, error: Exception.message(e)})
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, tick_interval())
  end

  defp tick_interval, do: Application.fetch_env!(:transport, :dynamic_irve_tick_interval)

  defp expected_columns, do: Transport.IRVE.DynamicIRVESchema.build_schema_fields_list()
end
