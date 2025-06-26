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

  def main(id), do: %__MODULE__{type: :main, id: id}

  @doc """
  iex> to_field(%Transport.Registry.Model.StopIdentifier{id: "stop1", type: :main})
  "main:stop1"
  iex> to_field(%Transport.Registry.Model.StopIdentifier{id: "FRPLY", type: :private_code})
  "private_code:FRPLY"
  iex> to_field(%Transport.Registry.Model.StopIdentifier{id: "PARIS GDL", type: :other})
  "other:PARIS GDL"
  """
  def to_field(%__MODULE__{id: id, type: type}) do
    "#{type}:#{id}"
  end
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

  def csv_headers do
    ~w(
      main_id
      display_name
      data_source_id
      data_source_format
      parent_id
      latitude
      longitude
      projection
      stop_type
    )
  end

  def to_csv(%__MODULE__{} = stop) do
    [
      StopIdentifier.to_field(stop.main_id),
      stop.display_name,
      stop.data_source_id,
      stop.data_source_format,
      maybe(stop.parent_id, &StopIdentifier.to_field/1, ""),
      stop.latitude,
      stop.longitude,
      stop.projection,
      stop.stop_type
    ]
  end

  @spec maybe(value :: any() | nil, mapper :: (any() -> any()), defaultValue :: any()) :: any() | nil
  def maybe(nil, _, defaultValue), do: defaultValue
  def maybe(value, mapper, _), do: mapper.(value)
end
