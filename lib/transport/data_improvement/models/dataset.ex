defmodule Transport.DataImprovement.Dataset do
  @moduledoc """
  A dataset in the context of data improvement.
  """

  defstruct [:dataset_id, :file]
  use Transport.DataImprovement.Macros, :model

  @type t :: %__MODULE__{
    dataset_id: String.t,
    file: String.t
  }
end
