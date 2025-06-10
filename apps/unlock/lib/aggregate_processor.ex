defmodule Unlock.AggregateProcessor do
  @moduledoc """
  The aggregate processor is able to consolidate (Dynamic IRVE CSV only for now, but the name has been kept
  generic as it could quite be made generic) multiple feeds as one.
  """

  require Logger

  # We actually look into the schema to build this. This is preliminary work
  # to add live validation later here.
  @schema_fields Unlock.DynamicIRVESchema.build_schema_fields_list()

  @doc """
  Given an aggregate item, achieve concurrent querying of all sub-items and consolidate the outputs.

  This implementation safely handles technical errors, non-200 responses and timeouts by returning empty
  lists so that the consolidated feed is still made available.

  Each sub-item result is cached in its own `Cachex` key.

  The consolidated feed isn't cached, on purpose at the moment, because it allows a bit of dynamic behaviour
  which is helpful (we will still be able to cache the global feed later, but if we do so we will want to
  make sure the overall TTL does not increase too much).

  NOTE: special care will be needed as we add more feeds, if the risk of timeout increases: the total
  computation delay, in case of timeouts, will increase accordingly, as the global consolidation has to
  wait for each timed-out item to reach its timeout (5 seconds currently).
  """
  def process_resource(%Unlock.Config.Item.Aggregate{} = item, options \\ []) do
    options =
      Keyword.validate!(options, [
        :limit_per_source,
        :include_origin
      ])

    comp_fn = fn _key ->
      {:commit, fetch_feeds(item, options), ttl: :timer.seconds(item.ttl)}
    end

    cache_name = Unlock.Shared.cache_name()
    cache_key = item.identifier <> ":#{:erlang.phash2(options)}"

    case Cachex.fetch(cache_name, cache_key, comp_fn) do
      {:ok, result} ->
        Logger.info("Proxy response for #{item.identifier} served from cache")
        result

      {:commit, result, _options} ->
        result

      {:error, _error} ->
        Logger.error("Error while fetching key #{cache_key}")
        %Unlock.HTTP.Response{status: 502, body: "", headers: []}
    end
  end

  def fetch_feeds(%Unlock.Config.Item.Aggregate{} = item, options) do
    headers = @schema_fields
    headers = if options[:include_origin], do: headers ++ ["origin", "slug"], else: headers

    rows_stream =
      item.feeds
      |> Task.async_stream(
        &process_sub_item(item, &1, options),
        max_concurrency: 10,
        # this is the default, but highlighted for maintenance clarity
        ordered: true,
        # allow override from tests, default to 5 seconds which is `async_stream` default
        timeout: Process.get(:override_aggregate_processor_async_timeout, 5_000),
        # only kill the relevant sub-task, not the whole processing
        on_timeout: :kill_task,
        # make sure to pass the sub-item to the exit (used for logging)
        zip_input_on_exit: true
      )
      |> Stream.map(fn
        {:ok, stream} ->
          stream

        {:exit, {sub_item, :timeout}} ->
          Logger.warning("Timeout for origin #{sub_item.identifier}, response has been dropped")
          []
      end)
      |> Stream.concat()

    [headers]
    |> Stream.concat(rows_stream)
    |> Enum.into([])
    |> NimbleCSV.RFC4180.dump_to_iodata()
  end

  @doc """
  Probably one of the most complicated parts of the proxy.

  A computation function is built to query the data via HTTP, but only if `Cachex`
  asks for it (based on expiry dates & TTL registered with the caching key).

  `Cachex` ensures uniqueness of concurrent calls & RAM storage, returning tuples to
  hint us what happened.

  This code needs to be DRYed ultimately (see `Controller.fetch_remote`), and simplified
  via an extraction of the caching logic in a specific place.
  """
  def cached_fetch(
        %Unlock.Config.Item.Aggregate{} = item,
        %Unlock.Config.Item.Generic.HTTP{identifier: origin} = sub_item
      ) do
    comp_fn = fn _key ->
      Unlock.Telemetry.trace_request([item.identifier, origin], :internal)
      Unlock.CachedFetch.fetch_data(sub_item, max_redirects: 2)
    end

    cache_name = Unlock.Shared.cache_name()
    cache_key = Unlock.Shared.cache_key(item.identifier, origin)
    outcome = Cachex.fetch(cache_name, cache_key, comp_fn)

    case outcome do
      {:ok, result} ->
        Logger.info("Proxy response for #{item.identifier}:#{origin} served from cache")
        result

      {:commit, result, _options} ->
        result

      {:ignore, result} ->
        # Too large - not expected to occur in nominal circumstances
        Logger.info("Cache has been skipped for proxy response")
        result

      {:error, _error} ->
        # NOTE: we'll want to have some monitoring here, but not using Sentry
        # because in case of troubles, we will blow up our quota.
        Logger.error("Error while fetching key #{cache_key}")
        # Bad gateway - which will be processed upstream
        %Unlock.HTTP.Response{status: 502, body: "", headers: []}
    end
  end

  @doc """
  Process a sub-item (sub-feed of the aggregate item), "safely" returning an empty list
  should any error occur.
  """
  def process_sub_item(
        %Unlock.Config.Item.Aggregate{} = item,
        %Unlock.Config.Item.Generic.HTTP{identifier: origin, slug: slug} = sub_item,
        options
      ) do
    Logger.debug("Fetching aggregated sub-item #{slug}/#{origin} at #{sub_item.target_url}")

    %{status: status, body: body} =
      cached_fetch(item, %Unlock.Config.Item.Generic.HTTP{identifier: origin} = sub_item)

    Logger.debug("#{slug}/#{origin} responded with HTTP code #{status} (#{body |> byte_size} bytes)")

    if status == 200 do
      # NOTE: at this point of deployment, having a log in case of error will be good enough.
      # We can later expose to the public with an alternate sub-url for observability.
      try do
        process_csv_payload(body, origin, slug, options)
      catch
        {:non_matching_headers, headers} ->
          Logger.info("Broken stream for origin #{slug}/#{origin} (headers are #{headers |> inspect})")
          []
      end
    else
      Logger.info("Non-200 response for origin #{slug}/#{origin} (status=#{status}), response has been dropped")
      []
    end
  rescue
    # Since the code is ran via `Task.async_stream`, we wrap it with a rescue block, otherwise
    # the whole consolidated response will stop and a 500 will be generated
    e ->
      Logger.warning(
        "Error occurred during processing origin #{slug}/#{origin} (#{e |> inspect}), response has been dropped"
      )

      []
  end

  # NOTE: we could avoid "decoding" the payload, but doing so will allow us
  # to integrate live validation (e.g. of id_pdc_itinerance against static database)
  # more easily, with less refactoring.
  def process_csv_payload(body, origin, slug, options \\ []) do
    # NOTE: currently fully in RAM - an improvement point for later
    [headers | rows] = NimbleCSV.RFC4180.parse_string(body, skip_headers: false)

    # SEE: https://specs.frictionlessdata.io/table-schema/#descriptor
    # The order of elements in fields array SHOULD be the order of fields in the CSV file.
    # The number of elements in fields array SHOULD be the same as the number of fields in the CSV file.

    # once we assert that, the rest of the processing is easy
    unless headers == @schema_fields do
      throw({:non_matching_headers, headers})
    end

    # Only keeping the id for now, on purpose
    rows = if options[:limit_per_source], do: Stream.take(rows, options[:limit_per_source]), else: rows

    mapper =
      if options[:include_origin] do
        fn columns -> columns ++ [origin, slug] end
      else
        fn columns -> columns end
      end

    rows
    |> Stream.map(mapper)
  end
end
