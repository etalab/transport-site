defmodule Transport.Registry.Model.DataSource do
  @moduledoc """
  Common attributes describing a data source.
  """

  defstruct [
    :id,
    :checksum,
    :last_updated_at,
    :validity_period
  ]

  @type t :: %__MODULE__{
          id: data_source_id(),
          checksum: binary(),
          last_updated_at: DateTime.t(),
          validity_period: date_time_range()
        }

  @type data_source_id :: binary()

  @type date_time_range :: binary()
end
