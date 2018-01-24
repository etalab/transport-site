defmodule Transport.DataValidation.Queries.FindProject do
  @moduledoc """
  Query for finding a project.

  ## Examples

      iex> %FindProject{}
      %FindProject{}

      iex> %FindProject{name: "transport"}
      %FindProject{name: "transport"}

  """

  defstruct [:name]
end
