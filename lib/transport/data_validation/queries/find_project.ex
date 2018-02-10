defmodule Transport.DataValidation.Queries.FindProject do
  @moduledoc """
  Query for finding a project.

  ## Examples

      iex> %{name: "transport"}
      ...> |> FindProject.new
      %FindProject{name: "transport"}

  """

  defstruct [:name]

  use ExConstructor

  @type t :: %__MODULE__{
    name: String.t
  }
end
