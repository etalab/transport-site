defmodule Transport.DataValidation.Queries.FindFeedVersion do
  @moduledoc """
  Query for finding a feed version.

  ## Examples

      iex> %{project: %Project{id: "1"}, latest_version_id: "gtfs-a89633616334.zip"}
      ...> |> FindFeedVersion.new
      %FindFeedVersion{project: %Project{id: "1"}, name: "gtfs-a89633616334.zip"}

  """

  defstruct [:project, :latest_version_id]

  use ExConstructor
  alias Transport.DataValidation.Aggregates.Project

  @type t :: %__MODULE__{
    project: Project.t,
    latest_version_id: String.t
  }
end
