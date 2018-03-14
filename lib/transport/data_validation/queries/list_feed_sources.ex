defmodule Transport.DataValidation.Queries.ListFeedSources do
  @moduledoc """
  Query for listing the feed sources.

  ## Examples

      iex> %{project: %Project{id: "1"}}
      ...> |> ListFeedSources.new
      %ListFeedSources{project: %Project{id: "1"}}

  """

  defstruct [:project]

  use ExConstructor
  alias Transport.DataValidation.Aggregates.Project

  @type t :: %__MODULE__{
    project: Project.t
  }
end
