defmodule TransitRealtime.FeedHeader.Incrementality do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto2

  @type t :: integer | :FULL_DATASET | :DIFFERENTIAL

  field(:FULL_DATASET, 0)
  field(:DIFFERENTIAL, 1)
end

defmodule TransitRealtime.TripUpdate.StopTimeUpdate.ScheduleRelationship do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto2

  @type t :: integer | :SCHEDULED | :SKIPPED | :NO_DATA

  field(:SCHEDULED, 0)
  field(:SKIPPED, 1)
  field(:NO_DATA, 2)
end

defmodule TransitRealtime.VehiclePosition.VehicleStopStatus do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto2

  @type t :: integer | :INCOMING_AT | :STOPPED_AT | :IN_TRANSIT_TO

  field(:INCOMING_AT, 0)
  field(:STOPPED_AT, 1)
  field(:IN_TRANSIT_TO, 2)
end

defmodule TransitRealtime.VehiclePosition.CongestionLevel do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto2

  @type t ::
          integer
          | :UNKNOWN_CONGESTION_LEVEL
          | :RUNNING_SMOOTHLY
          | :STOP_AND_GO
          | :CONGESTION
          | :SEVERE_CONGESTION

  field(:UNKNOWN_CONGESTION_LEVEL, 0)
  field(:RUNNING_SMOOTHLY, 1)
  field(:STOP_AND_GO, 2)
  field(:CONGESTION, 3)
  field(:SEVERE_CONGESTION, 4)
end

defmodule TransitRealtime.VehiclePosition.OccupancyStatus do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto2

  @type t ::
          integer
          | :EMPTY
          | :MANY_SEATS_AVAILABLE
          | :FEW_SEATS_AVAILABLE
          | :STANDING_ROOM_ONLY
          | :CRUSHED_STANDING_ROOM_ONLY
          | :FULL
          | :NOT_ACCEPTING_PASSENGERS

  field(:EMPTY, 0)
  field(:MANY_SEATS_AVAILABLE, 1)
  field(:FEW_SEATS_AVAILABLE, 2)
  field(:STANDING_ROOM_ONLY, 3)
  field(:CRUSHED_STANDING_ROOM_ONLY, 4)
  field(:FULL, 5)
  field(:NOT_ACCEPTING_PASSENGERS, 6)
end

defmodule TransitRealtime.Alert.Cause do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto2

  @type t ::
          integer
          | :UNKNOWN_CAUSE
          | :OTHER_CAUSE
          | :TECHNICAL_PROBLEM
          | :STRIKE
          | :DEMONSTRATION
          | :ACCIDENT
          | :HOLIDAY
          | :WEATHER
          | :MAINTENANCE
          | :CONSTRUCTION
          | :POLICE_ACTIVITY
          | :MEDICAL_EMERGENCY

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
  use Protobuf, enum: true, syntax: :proto2

  @type t ::
          integer
          | :NO_SERVICE
          | :REDUCED_SERVICE
          | :SIGNIFICANT_DELAYS
          | :DETOUR
          | :ADDITIONAL_SERVICE
          | :MODIFIED_SERVICE
          | :OTHER_EFFECT
          | :UNKNOWN_EFFECT
          | :STOP_MOVED

  field(:NO_SERVICE, 1)
  field(:REDUCED_SERVICE, 2)
  field(:SIGNIFICANT_DELAYS, 3)
  field(:DETOUR, 4)
  field(:ADDITIONAL_SERVICE, 5)
  field(:MODIFIED_SERVICE, 6)
  field(:OTHER_EFFECT, 7)
  field(:UNKNOWN_EFFECT, 8)
  field(:STOP_MOVED, 9)
end

defmodule TransitRealtime.TripDescriptor.ScheduleRelationship do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto2

  @type t :: integer | :SCHEDULED | :ADDED | :UNSCHEDULED | :CANCELED

  field(:SCHEDULED, 0)
  field(:ADDED, 1)
  field(:UNSCHEDULED, 2)
  field(:CANCELED, 3)
end

defmodule TransitRealtime.FeedMessage do
  @moduledoc false
  use Protobuf, syntax: :proto2

  @type t :: %__MODULE__{
          header: TransitRealtime.FeedHeader.t() | nil,
          entity: [TransitRealtime.FeedEntity.t()],
          __pb_extensions__: map
        }

  defstruct header: nil,
            entity: [],
            __pb_extensions__: nil

  field(:header, 1, required: true, type: TransitRealtime.FeedHeader)
  field(:entity, 2, repeated: true, type: TransitRealtime.FeedEntity)

  extensions([{1000, 2000}])
end

defmodule TransitRealtime.FeedHeader do
  @moduledoc false
  use Protobuf, syntax: :proto2

  @type t :: %__MODULE__{
          gtfs_realtime_version: String.t(),
          incrementality: TransitRealtime.FeedHeader.Incrementality.t(),
          timestamp: non_neg_integer,
          __pb_extensions__: map
        }

  defstruct gtfs_realtime_version: "",
            incrementality: nil,
            timestamp: nil,
            __pb_extensions__: nil

  field(:gtfs_realtime_version, 1, required: true, type: :string)

  field(:incrementality, 2,
    optional: true,
    type: TransitRealtime.FeedHeader.Incrementality,
    default: :FULL_DATASET,
    enum: true
  )

  field(:timestamp, 3, optional: true, type: :uint64)

  extensions([{1000, 2000}])
end

defmodule TransitRealtime.FeedEntity do
  @moduledoc false
  use Protobuf, syntax: :proto2

  @type t :: %__MODULE__{
          id: String.t(),
          is_deleted: boolean,
          trip_update: TransitRealtime.TripUpdate.t() | nil,
          vehicle: TransitRealtime.VehiclePosition.t() | nil,
          alert: TransitRealtime.Alert.t() | nil,
          __pb_extensions__: map
        }

  defstruct id: "",
            is_deleted: nil,
            trip_update: nil,
            vehicle: nil,
            alert: nil,
            __pb_extensions__: nil

  field(:id, 1, required: true, type: :string)
  field(:is_deleted, 2, optional: true, type: :bool, default: false)
  field(:trip_update, 3, optional: true, type: TransitRealtime.TripUpdate)
  field(:vehicle, 4, optional: true, type: TransitRealtime.VehiclePosition)
  field(:alert, 5, optional: true, type: TransitRealtime.Alert)

  extensions([{1000, 2000}])
end

defmodule TransitRealtime.TripUpdate.StopTimeEvent do
  @moduledoc false
  use Protobuf, syntax: :proto2

  @type t :: %__MODULE__{
          delay: integer,
          time: integer,
          uncertainty: integer,
          __pb_extensions__: map
        }

  defstruct delay: nil,
            time: nil,
            uncertainty: nil,
            __pb_extensions__: nil

  field(:delay, 1, optional: true, type: :int32)
  field(:time, 2, optional: true, type: :int64)
  field(:uncertainty, 3, optional: true, type: :int32)

  extensions([{1000, 2000}])
end

defmodule TransitRealtime.TripUpdate.StopTimeUpdate do
  @moduledoc false
  use Protobuf, syntax: :proto2

  @type t :: %__MODULE__{
          stop_sequence: non_neg_integer,
          stop_id: String.t(),
          arrival: TransitRealtime.TripUpdate.StopTimeEvent.t() | nil,
          departure: TransitRealtime.TripUpdate.StopTimeEvent.t() | nil,
          schedule_relationship: TransitRealtime.TripUpdate.StopTimeUpdate.ScheduleRelationship.t(),
          __pb_extensions__: map
        }

  defstruct stop_sequence: nil,
            stop_id: nil,
            arrival: nil,
            departure: nil,
            schedule_relationship: nil,
            __pb_extensions__: nil

  field(:stop_sequence, 1, optional: true, type: :uint32)
  field(:stop_id, 4, optional: true, type: :string)
  field(:arrival, 2, optional: true, type: TransitRealtime.TripUpdate.StopTimeEvent)
  field(:departure, 3, optional: true, type: TransitRealtime.TripUpdate.StopTimeEvent)

  field(:schedule_relationship, 5,
    optional: true,
    type: TransitRealtime.TripUpdate.StopTimeUpdate.ScheduleRelationship,
    default: :SCHEDULED,
    enum: true
  )

  extensions([{1000, 2000}])
end

defmodule TransitRealtime.TripUpdate do
  @moduledoc false
  use Protobuf, syntax: :proto2

  @type t :: %__MODULE__{
          trip: TransitRealtime.TripDescriptor.t() | nil,
          vehicle: TransitRealtime.VehicleDescriptor.t() | nil,
          stop_time_update: [TransitRealtime.TripUpdate.StopTimeUpdate.t()],
          timestamp: non_neg_integer,
          delay: integer,
          __pb_extensions__: map
        }

  defstruct trip: nil,
            vehicle: nil,
            stop_time_update: [],
            timestamp: nil,
            delay: nil,
            __pb_extensions__: nil

  field(:trip, 1, required: true, type: TransitRealtime.TripDescriptor)
  field(:vehicle, 3, optional: true, type: TransitRealtime.VehicleDescriptor)
  field(:stop_time_update, 2, repeated: true, type: TransitRealtime.TripUpdate.StopTimeUpdate)
  field(:timestamp, 4, optional: true, type: :uint64)
  field(:delay, 5, optional: true, type: :int32)

  extensions([{1000, 2000}])
end

defmodule TransitRealtime.VehiclePosition do
  @moduledoc false
  use Protobuf, syntax: :proto2

  @type t :: %__MODULE__{
          trip: TransitRealtime.TripDescriptor.t() | nil,
          vehicle: TransitRealtime.VehicleDescriptor.t() | nil,
          position: TransitRealtime.Position.t() | nil,
          current_stop_sequence: non_neg_integer,
          stop_id: String.t(),
          current_status: TransitRealtime.VehiclePosition.VehicleStopStatus.t(),
          timestamp: non_neg_integer,
          congestion_level: TransitRealtime.VehiclePosition.CongestionLevel.t(),
          occupancy_status: TransitRealtime.VehiclePosition.OccupancyStatus.t(),
          __pb_extensions__: map
        }

  defstruct trip: nil,
            vehicle: nil,
            position: nil,
            current_stop_sequence: nil,
            stop_id: nil,
            current_status: nil,
            timestamp: nil,
            congestion_level: nil,
            occupancy_status: nil,
            __pb_extensions__: nil

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

  extensions([{1000, 2000}])
end

defmodule TransitRealtime.Alert do
  @moduledoc false
  use Protobuf, syntax: :proto2

  @type t :: %__MODULE__{
          active_period: [TransitRealtime.TimeRange.t()],
          informed_entity: [TransitRealtime.EntitySelector.t()],
          cause: TransitRealtime.Alert.Cause.t(),
          effect: TransitRealtime.Alert.Effect.t(),
          url: TransitRealtime.TranslatedString.t() | nil,
          header_text: TransitRealtime.TranslatedString.t() | nil,
          description_text: TransitRealtime.TranslatedString.t() | nil,
          __pb_extensions__: map
        }

  defstruct active_period: [],
            informed_entity: [],
            cause: nil,
            effect: nil,
            url: nil,
            header_text: nil,
            description_text: nil,
            __pb_extensions__: nil

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

  extensions([{1000, 2000}])
end

defmodule TransitRealtime.TimeRange do
  @moduledoc false
  use Protobuf, syntax: :proto2

  @type t :: %__MODULE__{
          start: non_neg_integer,
          end: non_neg_integer,
          __pb_extensions__: map
        }

  defstruct start: nil,
            end: nil,
            __pb_extensions__: nil

  field(:start, 1, optional: true, type: :uint64)
  field(:end, 2, optional: true, type: :uint64)

  extensions([{1000, 2000}])
end

defmodule TransitRealtime.Position do
  @moduledoc false
  use Protobuf, syntax: :proto2

  @type t :: %__MODULE__{
          latitude: float | :infinity | :negative_infinity | :nan,
          longitude: float | :infinity | :negative_infinity | :nan,
          bearing: float | :infinity | :negative_infinity | :nan,
          odometer: float | :infinity | :negative_infinity | :nan,
          speed: float | :infinity | :negative_infinity | :nan,
          __pb_extensions__: map
        }

  defstruct latitude: 0.0,
            longitude: 0.0,
            bearing: nil,
            odometer: nil,
            speed: nil,
            __pb_extensions__: nil

  field(:latitude, 1, required: true, type: :float)
  field(:longitude, 2, required: true, type: :float)
  field(:bearing, 3, optional: true, type: :float)
  field(:odometer, 4, optional: true, type: :double)
  field(:speed, 5, optional: true, type: :float)

  extensions([{1000, 2000}])
end

defmodule TransitRealtime.TripDescriptor do
  @moduledoc false
  use Protobuf, syntax: :proto2

  @type t :: %__MODULE__{
          trip_id: String.t(),
          route_id: String.t(),
          direction_id: non_neg_integer,
          start_time: String.t(),
          start_date: String.t(),
          schedule_relationship: TransitRealtime.TripDescriptor.ScheduleRelationship.t(),
          __pb_extensions__: map
        }

  defstruct trip_id: nil,
            route_id: nil,
            direction_id: nil,
            start_time: nil,
            start_date: nil,
            schedule_relationship: nil,
            __pb_extensions__: nil

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

  extensions([{1000, 2000}])
end

defmodule TransitRealtime.VehicleDescriptor do
  @moduledoc false
  use Protobuf, syntax: :proto2

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          license_plate: String.t(),
          __pb_extensions__: map
        }

  defstruct id: nil,
            label: nil,
            license_plate: nil,
            __pb_extensions__: nil

  field(:id, 1, optional: true, type: :string)
  field(:label, 2, optional: true, type: :string)
  field(:license_plate, 3, optional: true, type: :string)

  extensions([{1000, 2000}])
end

defmodule TransitRealtime.EntitySelector do
  @moduledoc false
  use Protobuf, syntax: :proto2

  @type t :: %__MODULE__{
          agency_id: String.t(),
          route_id: String.t(),
          route_type: integer,
          trip: TransitRealtime.TripDescriptor.t() | nil,
          stop_id: String.t(),
          __pb_extensions__: map
        }

  defstruct agency_id: nil,
            route_id: nil,
            route_type: nil,
            trip: nil,
            stop_id: nil,
            __pb_extensions__: nil

  field(:agency_id, 1, optional: true, type: :string)
  field(:route_id, 2, optional: true, type: :string)
  field(:route_type, 3, optional: true, type: :int32)
  field(:trip, 4, optional: true, type: TransitRealtime.TripDescriptor)
  field(:stop_id, 5, optional: true, type: :string)

  extensions([{1000, 2000}])
end

defmodule TransitRealtime.TranslatedString.Translation do
  @moduledoc false
  use Protobuf, syntax: :proto2

  @type t :: %__MODULE__{
          text: String.t(),
          language: String.t(),
          __pb_extensions__: map
        }

  defstruct text: "",
            language: nil,
            __pb_extensions__: nil

  field(:text, 1, required: true, type: :string)
  field(:language, 2, optional: true, type: :string)

  extensions([{1000, 2000}])
end

defmodule TransitRealtime.TranslatedString do
  @moduledoc false
  use Protobuf, syntax: :proto2

  @type t :: %__MODULE__{
          translation: [TransitRealtime.TranslatedString.Translation.t()],
          __pb_extensions__: map
        }

  defstruct translation: [],
            __pb_extensions__: nil

  field(:translation, 1, repeated: true, type: TransitRealtime.TranslatedString.Translation)

  extensions([{1000, 2000}])
end
