defmodule Transport.DataValidation.Commands.CreateFeedSource do
  @moduledoc """
  Command for creating a feed source.

  ## Examples

      iex> %{project: %Project{id: "1"}, name: "tisseo"}
      ...> |> CreateFeedSource.new
      ...> |> CreateFeedSource.validate
      {:ok, %CreateFeedSource{project: %Project{id: "1"}, name: "tisseo"}}

      iex> %{project: %Project{id: nil}, name: "tisseo"}
      ...> |> CreateFeedSource.new
      ...> |> CreateFeedSource.validate
      {:error, [{:error, :project, :by, "must exist"}]}

      iex> %{project: "1", name: "tisseo"}
      ...> |> CreateFeedSource.new
      ...> |> CreateFeedSource.validate
      {:error, [{:error, :project, :by, "must be a project"}, {:error, :project, :by, "must exist"}]}

      iex> %{project: %Project{id: "1"}}
      ...> |> CreateFeedSource.new
      ...> |> CreateFeedSource.validate
      {:error, [{:error, :name, :presence, "must be present"}]}

  """

  defstruct [:project, :name]

  use ExConstructor
  use Vex.Struct
  alias Transport.DataValidation.Aggregates.Project

  defdelegate validate(struct), to: Vex

  @type t :: %__MODULE__{
    project: Project.t,
    name: String.t
  }

  validates :project,
    by: &__MODULE__.validate_project_type/1,
    by: &__MODULE__.validate_project_existance/1

  validates :name, presence: true

  def validate_project_type(%Project{}), do: :ok
  def validate_project_type(_), do: {:error, "must be a project"}

  def validate_project_existance(%Project{} = %{id: id}) when is_binary(id), do: :ok
  def validate_project_existance(_), do: {:error, "must exist"}
end
