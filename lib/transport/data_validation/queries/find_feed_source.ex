defmodule Transport.DataValidation.Queries.FindFeedSource do
  @moduledoc """
  Query for finding a feed source.

  ## Examples

      iex> %{project: %Project{id: "1"}, name: "tisseo"}
      ...> |> FindFeedSource.new
      %FindFeedSource{project: %Project{id: "1"}, name: "tisseo"}

  """

  defstruct [:project, :name]

  use ExConstructor
  alias Transport.DataValidation.Aggregates.Project

  @type t :: %__MODULE__{
    project: Project.t,
    name: String.t
  }
end
