defmodule Transport.DataValidation.Aggregates.FeedSource do
  @moduledoc """
  A feed source represents an AO that publishes GTFS datasets.
  """

  defstruct [:id, :name, :url, :latest_version_id]
  use ExConstructor

  @type t :: %__MODULE__{
    id: String.t,
    name: String.t,
    url: String.t,
    latest_version_id: String.t
  }
end
