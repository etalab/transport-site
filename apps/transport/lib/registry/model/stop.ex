defmodule Transport.Registry.Model.StopIdentifier do
  @moduledoc """
  Representation of a Stop ID.
  """

  defstruct [
    :id,
    :type
  ]

  @type t :: %__MODULE__{
          id: binary(),
          type: identifier_type()
        }

  @type identifier_type :: :main | :private_code | :stop_code | :other
end

defmodule Transport.Registry.Model.Stop do
  @moduledoc """
  Common attributes describing a stop.
  """
  alias Transport.Registry.Model.DataSource
  alias Transport.Registry.Model.StopIdentifier

  defstruct [
    :main_id,
    :display_name,
    :data_source_id,
    :data_source_format,
    :parent_id,
    :latitude,
    :longitude,
    projection: :utm_wgs84,
    stop_type: :stop,
    secondary_ids: []
  ]

  @type t :: %__MODULE__{
          main_id: StopIdentifier.t(),
          display_name: binary(),
          data_source_id: DataSource.data_source_id(),
          data_source_format: data_source_format_type(),
          parent_id: StopIdentifier.t() | nil,
          latitude: float(),
          longitude: float(),
          projection: projection(),
          stop_type: stop_type(),
          secondary_ids: [StopIdentifier.t()]
        }

  @type data_source_format_type :: :gtfs | :netex

  @type stop_type :: :stop | :quay | :other

  @type projection :: :utm_wgs84 | :lambert93_rgf93
end
