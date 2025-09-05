defmodule TransportWeb.Live.GTFSDiffSelectLive.GTFSSpecification do
  @moduledoc """
  Component and helpers to display GTFS files.
  """
  use Phoenix.LiveView
  use Gettext, backend: TransportWeb.Gettext

  @standard_columns %{
    "agency.txt" => [
      "agency_id",
      "agency_name",
      "agency_url",
      "agency_timezone",
      "agency_lang",
      "agency_phone",
      "agency_fare_url",
      "agency_email"
    ],
    "stops.txt" => [
      "stop_id",
      "stop_code",
      "stop_name",
      "tts_stop_name",
      "stop_desc",
      "stop_lat",
      "stop_lon",
      "zone_id",
      "stop_url",
      "location_type",
      "parent_station",
      "stop_timezone",
      "wheelchair_boarding",
      "level_id",
      "platform_code"
    ],
    "routes.txt" => [
      "route_id",
      "agency_id",
      "route_short_name",
      "route_long_name",
      "route_desc",
      "route_type",
      "route_url",
      "route_color",
      "route_text_color",
      "route_sort_order",
      "continuous_pickup",
      "continuous_drop_off",
      "network_id"
    ],
    "trips.txt" => [
      "route_id",
      "service_id",
      "trip_id",
      "trip_headsign",
      "trip_short_name",
      "direction_id",
      "block_id",
      "shape_id",
      "wheelchair_accessible",
      "bikes_allowed"
    ],
    "stop_times.txt" => [
      "trip_id",
      "arrival_time",
      "departure_time",
      "stop_id",
      "location_group_id",
      "location_id",
      "stop_sequence",
      "stop_headsign",
      "start_pickup_drop_off_window",
      "end_pickup_drop_off_window",
      "pickup_type",
      "drop_off_type",
      "continuous_pickup",
      "continuous_drop_off",
      "shape_dist_traveled",
      "timepoint",
      "pickup_booking_rule_id",
      "drop_off_booking_rule_id"
    ],
    "calendar.txt" => [
      "service_id",
      "monday",
      "tuesday",
      "wednesday",
      "thursday",
      "friday",
      "saturday",
      "sunday",
      "start_date",
      "end_date"
    ],
    "calendar_dates.txt" => ["service_id", "date", "exception_type"],
    "fare_attributes.txt" => [
      "fare_id",
      "price",
      "currency_type",
      "payment_method",
      "transfers",
      "agency_id",
      "transfer_duration"
    ],
    "fare_rules.txt" => ["fare_id", "route_id", "origin_id", "destination_id", "contains_id"],
    "timeframes.txt" => ["timeframe_group_id", "start_time", "end_time", "service_id"],
    "rider_categories.txt" => [
      "rider_category_id",
      "rider_category_name",
      "is_default_fare_category",
      "eligibility_url"
    ],
    "fare_media.txt" => ["fare_media_id", "fare_media_name", "fare_media_type"],
    "fare_products.txt" => [
      "fare_product_id",
      "fare_product_name",
      "rider_category_id",
      "fare_media_id",
      "amount",
      "currency"
    ],
    "fare_leg_rules.txt" => [
      "leg_group_id",
      "network_id",
      "from_area_id",
      "to_area_id",
      "from_timeframe_group_id",
      "to_timeframe_group_id",
      "fare_product_id",
      "rule_priority"
    ],
    "fare_leg_join_rules.txt" => ["from_network_id", "to_network_id", "from_stop_id", "to_stop_id"],
    "fare_transfer_rules.txt" => [
      "from_leg_group_id",
      "to_leg_group_id",
      "transfer_count",
      "duration_limit",
      "duration_limit_type",
      "fare_transfer_type",
      "fare_product_id"
    ],
    "areas.txt" => ["area_id", "area_name"],
    "stop_areas.txt" => ["area_id", "stop_id"],
    "networks.txt" => ["network_id", "network_name"],
    "route_networks.txt" => ["network_id", "route_id"],
    "shapes.txt" => ["shape_id", "shape_pt_lat", "shape_pt_lon", "shape_pt_sequence", "shape_dist_traveled"],
    "frequencies.txt" => ["trip_id", "start_time", "end_time", "headway_secs", "exact_times"],
    "transfers.txt" => [
      "from_stop_id",
      "to_stop_id",
      "from_route_id",
      "to_route_id",
      "from_trip_id",
      "to_trip_id",
      "transfer_type",
      "min_transfer_time"
    ],
    "pathways.txt" => [
      "pathway_id",
      "from_stop_id",
      "to_stop_id",
      "pathway_mode",
      "is_bidirectional",
      "length",
      "traversal_time",
      "stair_count",
      "max_slope",
      "min_width",
      "signposted_as",
      "reversed_signposted_as"
    ],
    "levels.txt" => ["level_id", "level_index", "level_name"],
    "location_groups.txt" => ["location_group_id", "location_group_name"],
    "location_group_stops.txt" => ["location_group_id", "stop_id"],
    "booking_rules.txt" => [
      "booking_rule_id",
      "booking_type",
      "prior_notice_duration_min",
      "prior_notice_duration_max",
      "prior_notice_last_day",
      "prior_notice_last_time",
      "prior_notice_start_day",
      "prior_notice_start_time",
      "prior_notice_service_id",
      "message",
      "pickup_message",
      "drop_off_message",
      "phone_number",
      "info_url",
      "booking_url"
    ],
    "translations.txt" => [
      "table_name",
      "field_name",
      "language",
      "translation",
      "record_id",
      "record_sub_id",
      "field_value"
    ],
    "feed_info.txt" => [
      "feed_publisher_name",
      "feed_publisher_url",
      "feed_lang",
      "default_lang",
      "feed_start_date",
      "feed_end_date",
      "feed_version",
      "feed_contact_email",
      "feed_contact_url"
    ],
    "attributions.txt" => [
      "attribution_id",
      "agency_id",
      "route_id",
      "trip_id",
      "organization_name",
      "is_producer",
      "is_operator",
      "is_authority",
      "attribution_url",
      "attribution_email",
      "attribution_phone"
    ]
  }

  def standard_column?(file, column), do: column in Map.get(@standard_columns, file, [])

  def file_description(%{selected_file: _} = assigns) do
    ~H"""
    <h4><i class="symbol fa fa-file"></i> {@selected_file}</h4>
    <p>
      « <em>{description_text(@selected_file)}</em>
      »
      <a target="_blank" href={specification_url(@selected_file)}>
        {dgettext("gtfs-file-descriptions", "Know more about this file.")}
      </a>
    </p>
    """
  end

  defp description_text("agency.txt"), do: dgettext("gtfs-file-descriptions", "agency.txt")
  defp description_text("areas.txt"), do: dgettext("gtfs-file-descriptions", "areas.txt")
  defp description_text("attributions.txt"), do: dgettext("gtfs-file-descriptions", "attributions.txt")
  defp description_text("booking_rules.txt"), do: dgettext("gtfs-file-descriptions", "booking_rules.txt")
  defp description_text("calendar.txt"), do: dgettext("gtfs-file-descriptions", "calendar.txt")
  defp description_text("calendar_dates.txt"), do: dgettext("gtfs-file-descriptions", "calendar_dates.txt")
  defp description_text("fare_attributes.txt"), do: dgettext("gtfs-file-descriptions", "fare_attributes.txt")
  defp description_text("fare_leg_join_rules.txt"), do: dgettext("gtfs-file-descriptions", "fare_leg_join_rules.txt")
  defp description_text("fare_leg_rules.txt"), do: dgettext("gtfs-file-descriptions", "fare_leg_rules.txt")
  defp description_text("fare_media.txt"), do: dgettext("gtfs-file-descriptions", "fare_media.txt")
  defp description_text("fare_products.txt"), do: dgettext("gtfs-file-descriptions", "fare_products.txt")
  defp description_text("fare_rules.txt"), do: dgettext("gtfs-file-descriptions", "fare_rules.txt")
  defp description_text("fare_transfer_rules.txt"), do: dgettext("gtfs-file-descriptions", "fare_transfer_rules.txt")
  defp description_text("feed_info.txt"), do: dgettext("gtfs-file-descriptions", "feed_info.txt")
  defp description_text("frequencies.txt"), do: dgettext("gtfs-file-descriptions", "frequencies.txt")
  defp description_text("levels.txt"), do: dgettext("gtfs-file-descriptions", "levels.txt")
  defp description_text("location_group_stops.txt"), do: dgettext("gtfs-file-descriptions", "location_group_stops.txt")
  defp description_text("location_groups.txt"), do: dgettext("gtfs-file-descriptions", "location_groups.txt")
  defp description_text("networks.txt"), do: dgettext("gtfs-file-descriptions", "networks.txt")
  defp description_text("pathways.txt"), do: dgettext("gtfs-file-descriptions", "pathways.txt")
  defp description_text("rider_categories.txt"), do: dgettext("gtfs-file-descriptions", "rider_categories.txt")
  defp description_text("route_networks.txt"), do: dgettext("gtfs-file-descriptions", "route_networks.txt")
  defp description_text("routes.txt"), do: dgettext("gtfs-file-descriptions", "routes.txt")
  defp description_text("shapes.txt"), do: dgettext("gtfs-file-descriptions", "shapes.txt")
  defp description_text("stop_areas.txt"), do: dgettext("gtfs-file-descriptions", "stop_areas.txt")
  defp description_text("stop_times.txt"), do: dgettext("gtfs-file-descriptions", "stop_times.txt")
  defp description_text("stops.txt"), do: dgettext("gtfs-file-descriptions", "stops.txt")
  defp description_text("timeframes.txt"), do: dgettext("gtfs-file-descriptions", "timeframes.txt")
  defp description_text("transfers.txt"), do: dgettext("gtfs-file-descriptions", "transfers.txt")
  defp description_text("translations.txt"), do: dgettext("gtfs-file-descriptions", "translations.txt")
  defp description_text("trips.txt"), do: dgettext("gtfs-file-descriptions", "trips.txt")

  defp description_text(selected_file),
    do: dgettext("gtfs-file-descriptions", "unknown-file", unknown_file: selected_file)

  defp specification_url(file) do
    "https://gtfs.org/documentation/schedule/reference/##{String.replace(file, ".", "")}"
  end

  def route_type_short_description("0"), do: dgettext("gtfs-file-descriptions", "tram, streetcar, light rail")
  def route_type_short_description("1"), do: dgettext("gtfs-file-descriptions", "subway, metro")
  def route_type_short_description("2"), do: dgettext("gtfs-file-descriptions", "rail")
  def route_type_short_description("3"), do: dgettext("gtfs-file-descriptions", "bus")
  def route_type_short_description("4"), do: dgettext("gtfs-file-descriptions", "ferry")
  def route_type_short_description("5"), do: dgettext("gtfs-file-descriptions", "cable tram")
  def route_type_short_description("6"), do: dgettext("gtfs-file-descriptions", "aerial lift, suspended cable car")
  def route_type_short_description("7"), do: dgettext("gtfs-file-descriptions", "funicular")
  def route_type_short_description("11"), do: dgettext("gtfs-file-descriptions", "trolleybus")
  def route_type_short_description("12"), do: dgettext("gtfs-file-descriptions", "monorail")
  def route_type_short_description(_unexpected), do: dgettext("gtfs-file-descriptions", "unknown")

  def stop_location_type_short_description("0"), do: dgettext("gtfs-file-descriptions", "stop or platform")
  def stop_location_type_short_description("1"), do: dgettext("gtfs-file-descriptions", "station")
  def stop_location_type_short_description("2"), do: dgettext("gtfs-file-descriptions", "entrance/exit")
  def stop_location_type_short_description("3"), do: dgettext("gtfs-file-descriptions", "generic node")
  def stop_location_type_short_description("4"), do: dgettext("gtfs-file-descriptions", "boarding area")
  def stop_location_type_short_description(_unexpected), do: dgettext("gtfs-file-descriptions", "unknown")
end
