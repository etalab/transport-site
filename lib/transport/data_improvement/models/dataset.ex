defmodule Transport.DataImprovement.Dataset do
  @moduledoc """
  A dataset in the context of data improvement.
  """

  defstruct [:dataset_uuid, :file]
  use Transport.DataImprovement.Macros, :model

  @type t :: %__MODULE__{
    dataset_uuid: String.t,
    file: String.t
  }
end
