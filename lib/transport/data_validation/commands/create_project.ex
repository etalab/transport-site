defmodule Transport.DataValidation.Commands.CreateProject do
  @moduledoc """
  Command for creating a project.

  ## Examples

      iex> %{name: "transport"}
      ...> |> CreateProject.new
      ...> |> CreateProject.validate
      {:ok, %CreateProject{name: "transport"}}

      iex> %{name: "covoiturage", autoFetchFeeds: "true"}
      ...> |> CreateProject.new
      ...> |> CreateProject.validate
      {:ok, %CreateProject{name: "covoiturage"}}

      iex> %{}
      ...> |> CreateProject.new
      ...> |> CreateProject.validate
      {:error, [{:error, :name, :presence, "must be present"}]}

  """

  defstruct [:name]

  use ExConstructor
  use Vex.Struct

  defdelegate validate(struct), to: Vex

  @type t :: %__MODULE__{
    name: String.t
  }

  validates :name, presence: true
end
