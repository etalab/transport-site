defmodule Transport.DataValidation.Queries.FindFeedVersion do
  @moduledoc """
  Query for finding a feed version.

  ## Examples

      iex> %{project: %Project{id: "1"}, latest_version_id: "export-quotidien-au-format-gtfs-du-reseau-de-transport-lignes-d-azur-20180315T162637Z-16f8b757-1427-42d9-937f-a89633616334.zip"}
      ...> |> FindFeedVersion.new
      %FindFeedVersion{project: %Project{id: "1"}, name: "export-quotidien-au-format-gtfs-du-reseau-de-transport-lignes-d-azur-20180315T162637Z-16f8b757-1427-42d9-937f-a89633616334.zip"}

  """

  defstruct [:project, :latest_version_id]

  use ExConstructor
  alias Transport.DataValidation.Aggregates.Project

  @type t :: %__MODULE__{
    project: Project.t,
    latest_version_id: String.t
  }
end
