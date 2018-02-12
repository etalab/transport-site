defmodule Transport.DataValidation.Aggregates.FeedSource do
  @moduledoc """
  A feed source represents an AO that publishes GTFS datasets.
  """

  defstruct [:id, :name, :url]

  @type t :: %__MODULE__{
    id: String.t,
    name: String.t,
    url: String.t
  }
end
