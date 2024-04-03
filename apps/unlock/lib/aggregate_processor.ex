defmodule Unlock.AggregateProcessor do
  @moduledoc """
  The aggregate processor is able to consolidate (Dynamic IRVE CSV only for now, but the name has been kept
  generic as it could quite be made generic) multiple feeds as one.
  """

  require Logger

  def process_resource(item) do
    headers = ["id_pdc_itinerance"]

    rows =
      item.feeds
      |> Task.async_stream(
        fn sub_item ->
          Unlock.Telemetry.trace_request(item.identifier <> ":" <> sub_item["identifier"], :internal)
          Logger.debug("Fetching aggregated sub-item #{sub_item["identifier"]} at #{sub_item["target_url"]}")
          %{status: status, body: body} = get_with_maybe_redirect(sub_item |> Map.fetch!("target_url"))
          Logger.debug("#{sub_item["identifier"]} responded with HTTP code #{status} (#{body |> byte_size} bytes)")
          process_csv_payload(body)
        end,
        max_concurrency: 10,
        # this is the default, but highlighted for maintenance clarity
        ordered: true
      )
      |> Stream.map(fn {:ok, stream} -> stream end)
      |> Stream.concat()

    [headers]
    |> Stream.concat(rows)
    |> Enum.into([])
    |> NimbleCSV.RFC4180.dump_to_iodata()
  end

  # NOTE: we could avoid "decoding" the payload, but doing so will allow us
  # to integrate live validation (e.g. of id_pdc_itinerance against static database)
  # more easily, with less refactoring.
  def process_csv_payload(body, options \\ []) do
    [headers | rows] = NimbleCSV.RFC4180.parse_string(body, skip_headers: false)

    # SEE: https://specs.frictionlessdata.io/table-schema/#descriptor
    # The order of elements in fields array SHOULD be the order of fields in the CSV file.
    # The number of elements in fields array SHOULD be the same as the number of fields in the CSV file.

    # once we assert that, the rest of the processing is easy
    # TODO: handle errors gracefully
    ["id_pdc_itinerance" | _rest] = headers

    # Only keeping the id for now, on purpose
    rows = if options[:limit], do: Stream.take(rows, options[:limit]), else: rows

    rows
    |> Stream.map(fn [id | _rest] -> [id] end)
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
