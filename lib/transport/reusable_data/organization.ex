defmodule Transport.ReusableData.Organization do
  @moduledoc """
  Represents an organization.
  """

  defstruct [:name, :logo_thumbnail]
  use ExConstructor

  @type t :: %__MODULE__{
    name: String.t,
    logo_thumbnail: String.t
  }
end
