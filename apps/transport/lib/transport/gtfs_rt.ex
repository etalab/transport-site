defmodule Transport.GTFSRT do
  def decode_remote_feed(url) do
    case http_client().get(url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        data = TransitRealtime.FeedMessage.decode(body)
        # The only supported value for now is `FULL_DATASET`.
        # https://developers.google.com/transit/gtfs-realtime/reference#enum-incrementality
        %{gtfs_realtime_version: "2.0", incrementality: :FULL_DATASET} = data.header
        data

      _ ->
        :error
    end
  end

  def filter_feed(%TransitRealtime.FeedMessage{entity: entity}, type)
      when type in [:alerts, :trip_updates, :vehicle_positions] do
    types = %{alerts: :alert, trip_updates: :trip_update, vehicle_positions: :vehicle}
    field_to_use = Map.fetch!(types, type)
    entity |> Enum.map(&Map.fetch!(&1, field_to_use)) |> Enum.reject(&is_nil/1)
  end

  def alerts(%TransitRealtime.FeedMessage{} = feed) do
    filter_feed(feed, :alerts)
  end

  def trip_updates(%TransitRealtime.FeedMessage{} = feed) do
    filter_feed(feed, :trip_updates)
  end

  def vehicle_positions(%TransitRealtime.FeedMessage{} = feed) do
    filter_feed(feed, :vehicle_positions)
  end

  def has_alerts?(%TransitRealtime.FeedMessage{} = feed) do
    not Enum.empty?(alerts(feed))
  end

  def alerts_for_display(%TransitRealtime.FeedMessage{} = feed, requested_language \\ "fr") do
    # https://developers.google.com/transit/gtfs-realtime/reference#message-alert
    alerts(feed)
    |> Enum.map(fn %TransitRealtime.Alert{} = el ->
      %{
        effect: el.effect,
        cause: el.cause,
        header_text: best_translation(el.header_text, requested_language),
        description_text: best_translation(el.description_text, requested_language),
        url: el.url,
        is_active: is_active?(el.active_period),
        current_active_period: current_active_period(el.active_period)
      }
    end)
  end

  def best_translation(%TransitRealtime.TranslatedString{translation: translation}, requested_language)
      when is_binary(requested_language) do
    translation |> Enum.map(&fetch_translation(&1, requested_language)) |> Enum.reject(&is_nil(&1)) |> List.first()
  end

  def fetch_translation(
        %TransitRealtime.TranslatedString.Translation{language: language, text: text},
        requested_language
      )
      when is_binary(requested_language) do
    cond do
      requested_language == language -> text
      is_nil(language) -> text
      true -> nil
    end
  end

  def is_active?([]), do: true

  def is_active?([%TransitRealtime.TimeRange{}] = time_ranges) do
    time_ranges |> Enum.map(&is_current?/1) |> Enum.any?()
  end

  def current_active_period([%TransitRealtime.TimeRange{}] = time_ranges) do
    time_ranges
    |> Enum.filter(&is_current?/1)
    |> Enum.map(fn tr -> %{start: to_datetime(tr.start), end: to_datetime(tr.end)} end)
    |> List.first()
  end

  def to_datetime(nil), do: nil

  def to_datetime(timestamp) when is_integer(timestamp) do
    DateTime.from_unix!(timestamp)
  end

  def is_current?(%TransitRealtime.TimeRange{start: nil, end: nil}), do: true

  def is_current?(%TransitRealtime.TimeRange{start: start, end: nil}) when not is_nil(start) do
    DateTime.compare(to_datetime(start), DateTime.utc_now()) == :lt
  end

  def is_current?(%TransitRealtime.TimeRange{start: nil, end: date_end}) when not is_nil(date_end) do
    DateTime.compare(to_datetime(date_end), DateTime.utc_now()) == :gt
  end

  def is_current?(%TransitRealtime.TimeRange{start: date_start, end: date_end}) do
    DateTime.compare(to_datetime(date_start), DateTime.utc_now()) == :lt and
      DateTime.compare(to_datetime(date_end), DateTime.utc_now()) == :gt
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
