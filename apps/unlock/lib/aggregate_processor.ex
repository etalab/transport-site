defmodule Unlock.AggregateProcessor do
  @moduledoc """
  The aggregate processor is able to consolidate (Dynamic IRVE CSV only for now, but the name has been kept
  generic as it could quite be made generic) multiple feeds as one.
  """

  require Logger

  @schema_fields Unlock.DynamicIRVESchema.build_schema_fields_list()

  def process_resource(item, options \\ []) do
    options =
      Keyword.validate!(options, [
        :limit_per_source,
        :include_origin
      ])

    headers = @schema_fields
    headers = if options[:include_origin], do: headers ++ ["origin"], else: headers

    rows_stream =
      item.feeds
      |> Task.async_stream(
        &process_sub_item(item, &1, options),
        max_concurrency: 10,
        # this is the default, but highlighted for maintenance clarity
        ordered: true
        # TODO: handle timeouts here (log + "no op")
      )
      |> Stream.map(fn {:ok, stream} -> stream end)
      |> Stream.concat()

    [headers]
    |> Stream.concat(rows_stream)
    |> Enum.into([])
    |> NimbleCSV.RFC4180.dump_to_iodata()
  end

  def process_sub_item(item, sub_item, options) do
    origin = sub_item["identifier"]

    Unlock.Telemetry.trace_request(item.identifier <> ":" <> origin, :internal)
    Logger.debug("Fetching aggregated sub-item #{origin} at #{sub_item["target_url"]}")
    %{status: status, body: body} = get_with_maybe_redirect(sub_item |> Map.fetch!("target_url"))
    Logger.debug("#{origin} responded with HTTP code #{status} (#{body |> byte_size} bytes)")

    if status == 200 do
      # NOTE: at this point of deployment, having a log in case of error will be good enough.
      # We can later expose to the public with an alternate sub-url for observability.
      try do
        process_csv_payload(body, origin, options)
      catch
        {:non_matching_headers, headers} ->
          Logger.info("Broken stream for origin #{origin} (headers are #{headers |> inspect})")
          []
      end
    else
      Logger.info("Non-200 response for origin #{origin}, response has been dropped")
      []
    end
  end

  # NOTE: we could avoid "decoding" the payload, but doing so will allow us
  # to integrate live validation (e.g. of id_pdc_itinerance against static database)
  # more easily, with less refactoring.
  def process_csv_payload(body, origin, options \\ []) do
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
        fn columns -> columns ++ [origin] end
      else
        fn columns -> columns end
      end

    rows
    |> Stream.map(&mapper.(&1))
  end

  # `Finch` does not support redirects, and we likely will want to support data gouv stable urls
  # (unless we decide we don't want to rely on that too much). So instead of bringing `Req` here,
  # which we could also do later with a bit more work, it's easier to implement a home-baked redirect here.
  def get_with_maybe_redirect(url, remaining_tries \\ 2) do
    if remaining_tries == 0, do: raise("TooManyRedirect")

    case response = Unlock.HTTP.Client.impl().get!(url, []) do
      %{status: 302} ->
        [target_url] = for {"location", value} <- response.headers, do: value
        get_with_maybe_redirect(target_url, remaining_tries - 1)

      _ ->
        response
    end
  end
end
