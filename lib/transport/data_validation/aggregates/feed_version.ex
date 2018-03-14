defmodule Transport.DataValidation.Aggregates.FeedVersion do
  @moduledoc """
  A feed version is a specific version of a feed source.
  """

  defstruct [:namespace]
  use ExConstructor

  @type t :: %__MODULE__{
    namespace: String.t
  }
end
