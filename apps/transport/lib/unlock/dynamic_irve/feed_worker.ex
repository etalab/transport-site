defmodule Unlock.DynamicIRVE.FeedWorker do
  use GenServer
  require Logger

  def start_link(%Unlock.Config.Item.Generic.HTTP{} = feed) do
    GenServer.start_link(__MODULE__, feed, name: via(feed.slug))
  end

  def slug(pid), do: GenServer.call(pid, :slug)

  # Debug: Unlock.DynamicIRVE.FeedWorker.state("qualicharge")
  def state(slug), do: GenServer.call(via(slug), :state)

  defp via(slug), do: {:via, Registry, {Unlock.DynamicIRVE.Registry, slug}}

  @impl true
  def init(feed) do
    Logger.info("[DynamicIRVE] Feed worker started: #{feed.slug} (#{feed.identifier})")
    schedule_tick()
    {:ok, %{feed: feed, last_success_at: nil, last_error: nil}}
  end

  @impl true
  def handle_call(:slug, _from, %{feed: feed} = state), do: {:reply, feed.slug, state}
  def handle_call(:state, _from, state), do: {:reply, state, state}

  @impl true
  def handle_info(:tick, %{feed: feed} = state) do
    state = fetch_and_process(feed, state)
    schedule_tick()
    {:noreply, state}
  end

  # Catches HTTP errors and invalid CSV to avoid crashing the worker
  defp fetch_and_process(feed, state) do
    # decode_body: false keeps raw binary (Req still handles gzip decompression)
    case Req.get(feed.target_url, redirect_log_level: false, decode_body: false) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        # infer_schema_length: 0 → all columns as strings
        df = Explorer.DataFrame.load_csv!(body, infer_schema_length: 0)
        Logger.info("[DynamicIRVE] #{feed.slug} => HTTP 200, #{Explorer.DataFrame.n_rows(df)} rows, #{Explorer.DataFrame.n_columns(df)} cols")
        %{state | last_success_at: DateTime.utc_now(), last_error: nil}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("[DynamicIRVE] #{feed.slug} => HTTP #{status}")
        %{state | last_error: "HTTP #{status}"}

      {:error, reason} ->
        Logger.warning("[DynamicIRVE] #{feed.slug} => #{inspect(reason)}")
        %{state | last_error: inspect(reason)}
    end
  rescue
    e ->
      Logger.warning("[DynamicIRVE] #{feed.slug} => #{Exception.message(e)}")
      %{state | last_error: Exception.message(e)}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, tick_interval())
  end

  defp tick_interval, do: Application.fetch_env!(:transport, :dynamic_irve_tick_interval)
end
