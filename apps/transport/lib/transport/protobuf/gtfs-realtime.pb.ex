defmodule TransitRealtime.FeedHeader.Incrementality do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:FULL_DATASET, 0)
  field(:DIFFERENTIAL, 1)
end

defmodule TransitRealtime.TripUpdate.StopTimeUpdate.ScheduleRelationship do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:SCHEDULED, 0)
  field(:SKIPPED, 1)
  field(:NO_DATA, 2)
  field(:UNSCHEDULED, 3)
end

defmodule TransitRealtime.VehiclePosition.VehicleStopStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:INCOMING_AT, 0)
  field(:STOPPED_AT, 1)
  field(:IN_TRANSIT_TO, 2)
end

defmodule TransitRealtime.VehiclePosition.CongestionLevel do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:UNKNOWN_CONGESTION_LEVEL, 0)
  field(:RUNNING_SMOOTHLY, 1)
  field(:STOP_AND_GO, 2)
  field(:CONGESTION, 3)
  field(:SEVERE_CONGESTION, 4)
end

defmodule TransitRealtime.VehiclePosition.OccupancyStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:EMPTY, 0)
  field(:MANY_SEATS_AVAILABLE, 1)
  field(:FEW_SEATS_AVAILABLE, 2)
  field(:STANDING_ROOM_ONLY, 3)
  field(:CRUSHED_STANDING_ROOM_ONLY, 4)
  field(:FULL, 5)
  field(:NOT_ACCEPTING_PASSENGERS, 6)
  field(:NO_DATA_AVAILABLE, 7)
  field(:NOT_BOARDABLE, 8)
end

defmodule TransitRealtime.Alert.Cause do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:UNKNOWN_CAUSE, 1)
  field(:OTHER_CAUSE, 2)
  field(:TECHNICAL_PROBLEM, 3)
  field(:STRIKE, 4)
  field(:DEMONSTRATION, 5)
  field(:ACCIDENT, 6)
  field(:HOLIDAY, 7)
  field(:WEATHER, 8)
  field(:MAINTENANCE, 9)
  field(:CONSTRUCTION, 10)
  field(:POLICE_ACTIVITY, 11)
  field(:MEDICAL_EMERGENCY, 12)
end

defmodule TransitRealtime.Alert.Effect do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:NO_SERVICE, 1)
  field(:REDUCED_SERVICE, 2)
  field(:SIGNIFICANT_DELAYS, 3)
  field(:DETOUR, 4)
  field(:ADDITIONAL_SERVICE, 5)
  field(:MODIFIED_SERVICE, 6)
  field(:OTHER_EFFECT, 7)
  field(:UNKNOWN_EFFECT, 8)
  field(:STOP_MOVED, 9)
  field(:NO_EFFECT, 10)
  field(:ACCESSIBILITY_ISSUE, 11)
end

defmodule TransitRealtime.Alert.SeverityLevel do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:UNKNOWN_SEVERITY, 1)
  field(:INFO, 2)
  field(:WARNING, 3)
  field(:SEVERE, 4)
end

defmodule TransitRealtime.TripDescriptor.ScheduleRelationship do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:SCHEDULED, 0)
  field(:ADDED, 1)
  field(:UNSCHEDULED, 2)
  field(:CANCELED, 3)
  field(:REPLACEMENT, 5)
  field(:DUPLICATED, 6)
  field(:DELETED, 7)
end

defmodule TransitRealtime.VehicleDescriptor.WheelchairAccessible do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:NO_VALUE, 0)
  field(:UNKNOWN, 1)
  field(:WHEELCHAIR_ACCESSIBLE, 2)
  field(:WHEELCHAIR_INACCESSIBLE, 3)
end

defmodule TransitRealtime.Stop.WheelchairBoarding do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:UNKNOWN, 0)
  field(:AVAILABLE, 1)
  field(:NOT_AVAILABLE, 2)
end

defmodule TransitRealtime.FeedMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:header, 1, required: true, type: TransitRealtime.FeedHeader)
  field(:entity, 2, repeated: true, type: TransitRealtime.FeedEntity)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.FeedHeader do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:gtfs_realtime_version, 1, required: true, type: :string)

  field(:incrementality, 2,
    optional: true,
    type: TransitRealtime.FeedHeader.Incrementality,
    default: :FULL_DATASET,
    enum: true
  )

  field(:timestamp, 3, optional: true, type: :uint64)
  field(:feed_version, 4, optional: true, type: :string)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.FeedEntity do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:id, 1, required: true, type: :string)
  field(:is_deleted, 2, optional: true, type: :bool, default: false)
  field(:trip_update, 3, optional: true, type: TransitRealtime.TripUpdate)
  field(:vehicle, 4, optional: true, type: TransitRealtime.VehiclePosition)
  field(:alert, 5, optional: true, type: TransitRealtime.Alert)
  field(:shape, 6, optional: true, type: TransitRealtime.Shape)
  field(:stop, 7, optional: true, type: TransitRealtime.Stop)
  field(:trip_modifications, 8, optional: true, type: TransitRealtime.TripModifications)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.TripUpdate.StopTimeEvent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:delay, 1, optional: true, type: :int32)
  field(:time, 2, optional: true, type: :int64)
  field(:uncertainty, 3, optional: true, type: :int32)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.TripUpdate.StopTimeUpdate.StopTimeProperties do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:assigned_stop_id, 1, optional: true, type: :string)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.TripUpdate.StopTimeUpdate do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:stop_sequence, 1, optional: true, type: :uint32)
  field(:stop_id, 4, optional: true, type: :string)
  field(:arrival, 2, optional: true, type: TransitRealtime.TripUpdate.StopTimeEvent)
  field(:departure, 3, optional: true, type: TransitRealtime.TripUpdate.StopTimeEvent)

  field(:departure_occupancy_status, 7,
    optional: true,
    type: TransitRealtime.VehiclePosition.OccupancyStatus,
    enum: true
  )

  field(:schedule_relationship, 5,
    optional: true,
    type: TransitRealtime.TripUpdate.StopTimeUpdate.ScheduleRelationship,
    default: :SCHEDULED,
    enum: true
  )

  field(:stop_time_properties, 6,
    optional: true,
    type: TransitRealtime.TripUpdate.StopTimeUpdate.StopTimeProperties
  )

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.TripUpdate.TripProperties do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:trip_id, 1, optional: true, type: :string)
  field(:start_date, 2, optional: true, type: :string)
  field(:start_time, 3, optional: true, type: :string)
  field(:shape_id, 4, optional: true, type: :string)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.TripUpdate do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:trip, 1, required: true, type: TransitRealtime.TripDescriptor)
  field(:vehicle, 3, optional: true, type: TransitRealtime.VehicleDescriptor)
  field(:stop_time_update, 2, repeated: true, type: TransitRealtime.TripUpdate.StopTimeUpdate)
  field(:timestamp, 4, optional: true, type: :uint64)
  field(:delay, 5, optional: true, type: :int32)
  field(:trip_properties, 6, optional: true, type: TransitRealtime.TripUpdate.TripProperties)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.VehiclePosition.CarriageDetails do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:id, 1, optional: true, type: :string)
  field(:label, 2, optional: true, type: :string)

  field(:occupancy_status, 3,
    optional: true,
    type: TransitRealtime.VehiclePosition.OccupancyStatus,
    default: :NO_DATA_AVAILABLE,
    enum: true
  )

  field(:occupancy_percentage, 4, optional: true, type: :int32, default: -1)
  field(:carriage_sequence, 5, optional: true, type: :uint32)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.VehiclePosition do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:trip, 1, optional: true, type: TransitRealtime.TripDescriptor)
  field(:vehicle, 8, optional: true, type: TransitRealtime.VehicleDescriptor)
  field(:position, 2, optional: true, type: TransitRealtime.Position)
  field(:current_stop_sequence, 3, optional: true, type: :uint32)
  field(:stop_id, 7, optional: true, type: :string)

  field(:current_status, 4,
    optional: true,
    type: TransitRealtime.VehiclePosition.VehicleStopStatus,
    default: :IN_TRANSIT_TO,
    enum: true
  )

  field(:timestamp, 5, optional: true, type: :uint64)

  field(:congestion_level, 6,
    optional: true,
    type: TransitRealtime.VehiclePosition.CongestionLevel,
    enum: true
  )

  field(:occupancy_status, 9,
    optional: true,
    type: TransitRealtime.VehiclePosition.OccupancyStatus,
    enum: true
  )

  field(:occupancy_percentage, 10, optional: true, type: :uint32)

  field(:multi_carriage_details, 11,
    repeated: true,
    type: TransitRealtime.VehiclePosition.CarriageDetails
  )

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.Alert do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:active_period, 1, repeated: true, type: TransitRealtime.TimeRange)
  field(:informed_entity, 5, repeated: true, type: TransitRealtime.EntitySelector)

  field(:cause, 6,
    optional: true,
    type: TransitRealtime.Alert.Cause,
    default: :UNKNOWN_CAUSE,
    enum: true
  )

  field(:effect, 7,
    optional: true,
    type: TransitRealtime.Alert.Effect,
    default: :UNKNOWN_EFFECT,
    enum: true
  )

  field(:url, 8, optional: true, type: TransitRealtime.TranslatedString)
  field(:header_text, 10, optional: true, type: TransitRealtime.TranslatedString)
  field(:description_text, 11, optional: true, type: TransitRealtime.TranslatedString)
  field(:tts_header_text, 12, optional: true, type: TransitRealtime.TranslatedString)
  field(:tts_description_text, 13, optional: true, type: TransitRealtime.TranslatedString)

  field(:severity_level, 14,
    optional: true,
    type: TransitRealtime.Alert.SeverityLevel,
    default: :UNKNOWN_SEVERITY,
    enum: true
  )

  field(:image, 15, optional: true, type: TransitRealtime.TranslatedImage)
  field(:image_alternative_text, 16, optional: true, type: TransitRealtime.TranslatedString)
  field(:cause_detail, 17, optional: true, type: TransitRealtime.TranslatedString)
  field(:effect_detail, 18, optional: true, type: TransitRealtime.TranslatedString)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.TimeRange do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:start, 1, optional: true, type: :uint64)
  field(:end, 2, optional: true, type: :uint64)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.Position do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:latitude, 1, required: true, type: :float)
  field(:longitude, 2, required: true, type: :float)
  field(:bearing, 3, optional: true, type: :float)
  field(:odometer, 4, optional: true, type: :double)
  field(:speed, 5, optional: true, type: :float)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.TripDescriptor.ModifiedTripSelector do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:modifications_id, 1, optional: true, type: :string)
  field(:affected_trip_id, 2, optional: true, type: :string)
  field(:start_time, 3, optional: true, type: :string)
  field(:start_date, 4, optional: true, type: :string)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.TripDescriptor do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:trip_id, 1, optional: true, type: :string)
  field(:route_id, 5, optional: true, type: :string)
  field(:direction_id, 6, optional: true, type: :uint32)
  field(:start_time, 2, optional: true, type: :string)
  field(:start_date, 3, optional: true, type: :string)

  field(:schedule_relationship, 4,
    optional: true,
    type: TransitRealtime.TripDescriptor.ScheduleRelationship,
    enum: true
  )

  field(:modified_trip, 7,
    optional: true,
    type: TransitRealtime.TripDescriptor.ModifiedTripSelector
  )

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.VehicleDescriptor do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:id, 1, optional: true, type: :string)
  field(:label, 2, optional: true, type: :string)
  field(:license_plate, 3, optional: true, type: :string)

  field(:wheelchair_accessible, 4,
    optional: true,
    type: TransitRealtime.VehicleDescriptor.WheelchairAccessible,
    default: :NO_VALUE,
    enum: true
  )

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.EntitySelector do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:agency_id, 1, optional: true, type: :string)
  field(:route_id, 2, optional: true, type: :string)
  field(:route_type, 3, optional: true, type: :int32)
  field(:trip, 4, optional: true, type: TransitRealtime.TripDescriptor)
  field(:stop_id, 5, optional: true, type: :string)
  field(:direction_id, 6, optional: true, type: :uint32)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.TranslatedString.Translation do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:text, 1, required: true, type: :string)
  field(:language, 2, optional: true, type: :string)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.TranslatedString do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:translation, 1, repeated: true, type: TransitRealtime.TranslatedString.Translation)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.TranslatedImage.LocalizedImage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:url, 1, required: true, type: :string)
  field(:media_type, 2, required: true, type: :string)
  field(:language, 3, optional: true, type: :string)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.TranslatedImage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:localized_image, 1, repeated: true, type: TransitRealtime.TranslatedImage.LocalizedImage)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.Shape do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:shape_id, 1, optional: true, type: :string)
  field(:encoded_polyline, 2, optional: true, type: :string)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.Stop do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:stop_id, 1, optional: true, type: :string)
  field(:stop_code, 2, optional: true, type: TransitRealtime.TranslatedString)
  field(:stop_name, 3, optional: true, type: TransitRealtime.TranslatedString)
  field(:tts_stop_name, 4, optional: true, type: TransitRealtime.TranslatedString)
  field(:stop_desc, 5, optional: true, type: TransitRealtime.TranslatedString)
  field(:stop_lat, 6, optional: true, type: :float)
  field(:stop_lon, 7, optional: true, type: :float)
  field(:zone_id, 8, optional: true, type: :string)
  field(:stop_url, 9, optional: true, type: TransitRealtime.TranslatedString)
  field(:parent_station, 11, optional: true, type: :string)
  field(:stop_timezone, 12, optional: true, type: :string)

  field(:wheelchair_boarding, 13,
    optional: true,
    type: TransitRealtime.Stop.WheelchairBoarding,
    default: :UNKNOWN,
    enum: true
  )

  field(:level_id, 14, optional: true, type: :string)
  field(:platform_code, 15, optional: true, type: TransitRealtime.TranslatedString)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.TripModifications.Modification do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:start_stop_selector, 1, optional: true, type: TransitRealtime.StopSelector)
  field(:end_stop_selector, 2, optional: true, type: TransitRealtime.StopSelector)
  field(:propagated_modification_delay, 3, optional: true, type: :int32, default: 0)
  field(:replacement_stops, 4, repeated: true, type: TransitRealtime.ReplacementStop)
  field(:service_alert_id, 5, optional: true, type: :string)
  field(:last_modified_time, 6, optional: true, type: :uint64)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.TripModifications.SelectedTrips do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:trip_ids, 1, repeated: true, type: :string)
  field(:shape_id, 2, optional: true, type: :string)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.TripModifications do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:selected_trips, 1, repeated: true, type: TransitRealtime.TripModifications.SelectedTrips)
  field(:start_times, 2, repeated: true, type: :string)
  field(:service_dates, 3, repeated: true, type: :string)
  field(:modifications, 4, repeated: true, type: TransitRealtime.TripModifications.Modification)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.StopSelector do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:stop_sequence, 1, optional: true, type: :uint32)
  field(:stop_id, 2, optional: true, type: :string)

  extensions([{1000, 2000}, {9000, 10000}])
end

defmodule TransitRealtime.ReplacementStop do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.12.0", syntax: :proto2

  field(:travel_time_to_stop, 1, optional: true, type: :int32)
  field(:stop_id, 2, optional: true, type: :string)

  extensions([{1000, 2000}, {9000, 10000}])
end
