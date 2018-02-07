defmodule Transport.DataValidation.Commands.ValidateFeedVersion do
  @moduledoc """
  Command for validating a feed version.

  ## Examples

      iex> %{project: %Project{id: "1"}, id: "1"}
      ...> |> ValidateFeedVersion.new
      ...> |> ValidateFeedVersion.validate
      {:ok, %ValidateFeedVersion{project: %Project{id: "1"}, id: "1"}}

      iex> %{project: %Project{id: "1"}, id: "1", format: "netex"}
      ...> |> ValidateFeedVersion.new
      ...> |> ValidateFeedVersion.validate
      {:ok, %ValidateFeedVersion{project: %Project{id: "1"}, id: "1"}}

      iex> %{project: %Project{id: nil}, id: "1", format: "netex"}
      ...> |> ValidateFeedVersion.new
      ...> |> ValidateFeedVersion.validate
      {:error, [{:error, :project, :by, "must exist"}]}

      iex> %{project: "1", id: "1"}
      ...> |> ValidateFeedVersion.new
      ...> |> ValidateFeedVersion.validate
      {:error,
       [
         {:error, :project, :by, "must be a project"},
         {:error, :project, :by, "must exist"}
        ]}

      iex> %{}
      ...> |> ValidateFeedVersion.new
      ...> |> ValidateFeedVersion.validate
      {:error,
       [
         {:error, :id, :presence, "must be present"},
         {:error, :project, :by, "must be a project"},
         {:error, :project, :by, "must exist"}
       ]}

  """

  defstruct [:project, :id]

  use ExConstructor
  use Vex.Struct
  alias Transport.DataValidation.Aggregates.Project

  defdelegate validate(struct), to: Vex

  @type t :: %__MODULE__{
    project: Project.t,
    id: String.t
  }

  validates :project,
    by: &__MODULE__.validate_project_type/1,
    by: &__MODULE__.validate_project_existance/1

  validates :id, presence: true

  def validate_project_type(%Project{}), do: :ok
  def validate_project_type(_), do: {:error, "must be a project"}

  def validate_project_existance(%Project{} = %{id: id}) when is_binary(id), do: :ok
  def validate_project_existance(_), do: {:error, "must exist"}
end
