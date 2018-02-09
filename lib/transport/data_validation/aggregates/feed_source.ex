defmodule Transport.DataValidation.Aggregates.FeedSource do
  @moduledoc """
  A feed source represents an AO that publishes GTFS datasets.
  """

  defstruct [:id, :name]

  @type t :: %__MODULE__{
    id: String.t,
    name: String.t
  }
end
