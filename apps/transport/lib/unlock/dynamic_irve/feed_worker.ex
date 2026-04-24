defmodule Unlock.DynamicIRVE.FeedWorker do
  use GenServer
  require Logger

  alias Unlock.DynamicIRVE.FeedStore

  def start_link({parent_id, %Unlock.Config.Item.Generic.HTTP{} = feed}) do
    GenServer.start_link(__MODULE__, {parent_id, feed}, name: via({parent_id, feed.slug}))
  end

  defp via(key), do: {:via, Registry, {Unlock.DynamicIRVE.Registry, key}}

  @impl true
  def init({parent_id, feed}) do
    schedule_tick()
    {:ok, {parent_id, feed}}
  end

  @impl true
  def handle_info(:tick, {parent_id, feed} = state) do
    schedule_tick()
    fetch_and_process(parent_id, feed)
    {:noreply, state}
  end

  # Catches HTTP errors and invalid CSV to avoid crashing the worker
  defp fetch_and_process(parent_id, feed) do
    # decode_body: false keeps raw binary (Req still handles gzip decompression)
    case Req.get!(feed.target_url, redirect_log_level: false, decode_body: false) do
      %Req.Response{status: 200, body: body} ->
        # infer_schema_length: 0 → all columns as strings
        df =
          body
          |> Explorer.DataFrame.load_csv!(infer_schema_length: 0)
          |> Explorer.DataFrame.select(expected_columns())

        Logger.info(
          "[DynamicIRVE] #{parent_id}/#{feed.slug} => HTTP 200, #{Explorer.DataFrame.n_rows(df)} rows"
        )

        FeedStore.put_feed(parent_id, feed.slug, %{
          df: df,
          last_updated_at: DateTime.utc_now(),
          error: nil
        })

      %Req.Response{status: status} ->
        record_error(parent_id, feed.slug, "HTTP #{status}")
    end
  rescue
    e -> record_error(parent_id, feed.slug, Exception.message(e))
  end

  # Logs + stores the error, preserving the last good df/last_updated_at.
  defp record_error(parent_id, slug, message) do
    Logger.warning("[DynamicIRVE] #{parent_id}/#{slug} => #{message}")
    previous = FeedStore.get_feed(parent_id, slug) || %{df: nil, last_updated_at: nil}

    FeedStore.put_feed(
      parent_id,
      slug,
      Map.merge(previous, %{error: message, last_errored_at: DateTime.utc_now()})
    )
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, tick_interval())

  defp tick_interval, do: Application.fetch_env!(:transport, :dynamic_irve_tick_interval)

  defp expected_columns, do: Transport.IRVE.DynamicIRVESchema.build_schema_fields_list()
end
