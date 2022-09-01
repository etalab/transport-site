defmodule Transport.GTFSRT do
  @moduledoc """
  A module to work with GTFS-RT feeds.
  """
  require Logger
  alias TransitRealtime.{Alert, FeedMessage, TimeRange, TranslatedString}
  @entities [:service_alerts, :trip_updates, :vehicle_positions]

  @spec decode_remote_feed(binary()) :: {:ok, TransitRealtime.FeedMessage.t()} | {:error, binary()}
  def decode_remote_feed(url) do
    case http_client().get(url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        try do
          data = TransitRealtime.FeedMessage.decode(body)
          # The only supported value for now is `FULL_DATASET`.
          # https://developers.google.com/transit/gtfs-realtime/reference#enum-incrementality
          %{incrementality: :FULL_DATASET} = data.header
          {:ok, data}
        rescue
          e ->
            Logger.error(e)
            {:error, "Could not decode Protobuf"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code}} when status_code != 200 ->
        {:error, "Got a non 200 HTTP status code: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Got an HTTP error: #{reason}"}
    end
  end

  def timestamp(%FeedMessage{} = feed) do
    feed.header.timestamp |> DateTime.from_unix!()
  end

  @doc """
  Determines if a `FeedMessage` is too old, ie older than 5 minutes.

  iex> feed_is_too_old?(%TransitRealtime.FeedMessage{header: %TransitRealtime.FeedHeader{timestamp: 1661847898}}, DateTime.from_unix!(1661847899))
  false
  iex> feed_is_too_old?(%TransitRealtime.FeedMessage{header: %TransitRealtime.FeedHeader{timestamp: 1661847898}}, DateTime.from_unix!(1661848199))
  true
  """
  def feed_is_too_old?(%FeedMessage{} = feed, comparison \\ DateTime.utc_now()) do
    feed_timestamp_delay(feed, comparison) > 60 * 5
  end

  @doc """
  Number of seconds between the current datetime and the timestamp field of a feed.

  iex> feed_timestamp_delay(%TransitRealtime.FeedMessage{header: %TransitRealtime.FeedHeader{timestamp: 1661847898}}, DateTime.from_unix!(1661847899))
  1
  """
  def feed_timestamp_delay(%FeedMessage{} = feed, comparison \\ DateTime.utc_now()) do
    DateTime.diff(comparison, timestamp(feed), :second)
  end

  @doc """
  Count the number of entities in the feed.

  Example:
  ```
  %{service_alerts: 12, trip_updates: 0, vehicle_positions: 0}
  ```
  """
  def count_entities(%FeedMessage{} = feed) do
    @entities |> Enum.into(%{}, &{&1, feed |> filter_feed(&1) |> Enum.count()})
  end

  def filter_feed(%FeedMessage{entity: entity}, type) when type in @entities do
    types = %{service_alerts: :alert, trip_updates: :trip_update, vehicle_positions: :vehicle}
    field_to_use = Map.fetch!(types, type)
    entity |> Enum.map(&Map.fetch!(&1, field_to_use)) |> Enum.reject(&is_nil/1)
  end

  def service_alerts(%FeedMessage{} = feed) do
    filter_feed(feed, :service_alerts)
  end

  def trip_updates(%FeedMessage{} = feed) do
    filter_feed(feed, :trip_updates)
  end

  def vehicle_positions(%FeedMessage{} = feed) do
    filter_feed(feed, :vehicle_positions)
  end

  def has_service_alerts?(%FeedMessage{} = feed) do
    not Enum.empty?(service_alerts(feed))
  end

  def service_alerts_for_display(%FeedMessage{} = feed, requested_language \\ "fr") do
    # https://developers.google.com/transit/gtfs-realtime/reference#message-alert
    feed
    |> service_alerts()
    |> Enum.map(fn %Alert{} = el ->
      %{
        effect: el.effect,
        cause: el.cause,
        header_text: best_translation(el.header_text, requested_language),
        description_text: best_translation(el.description_text, requested_language),
        url: best_translation(el.url, requested_language),
        is_active: is_active?(el.active_period),
        current_active_period: current_active_period(el.active_period)
      }
    end)
  end

  def best_translation(nil, _), do: nil

  def best_translation(%TranslatedString{translation: translation}, requested_language)
      when is_binary(requested_language) do
    translation |> Enum.map(&fetch_translation(&1, requested_language)) |> Enum.reject(&is_nil(&1)) |> List.first()
  end

  def fetch_translation(
        %TranslatedString.Translation{language: language, text: text},
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

  def is_active?(time_ranges) do
    time_ranges |> Enum.map(&is_current?/1) |> Enum.any?()
  end

  def current_active_period(time_ranges) do
    time_ranges
    |> Enum.filter(&is_current?/1)
    |> Enum.map(fn tr -> %{start: to_datetime(tr.start), end: to_datetime(tr.end)} end)
    |> List.first()
  end

  defp to_datetime(nil), do: nil

  defp to_datetime(timestamp) when is_integer(timestamp) do
    DateTime.from_unix!(timestamp)
  end

  def is_current?(%TimeRange{start: nil, end: nil}), do: true

  def is_current?(%TimeRange{start: start, end: nil}) when not is_nil(start) do
    DateTime.compare(to_datetime(start), DateTime.utc_now()) == :lt
  end

  def is_current?(%TimeRange{start: nil, end: date_end}) when not is_nil(date_end) do
    DateTime.compare(to_datetime(date_end), DateTime.utc_now()) == :gt
  end

  def is_current?(%TimeRange{start: date_start, end: date_end}) do
    is_current?(%TimeRange{start: date_start}) and is_current?(%TimeRange{end: date_end})
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
