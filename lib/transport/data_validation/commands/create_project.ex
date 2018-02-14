defmodule Transport.DataValidation.Commands.CreateProject do
  @moduledoc """
  Command for creating a project.

  ## Examples

      iex> %{name: "transport"}
      ...> |> CreateProject.new
      ...> |> CreateProject.validate
      {:ok, %CreateProject{name: "transport"}}

      iex> %{}
      ...> |> CreateProject.new
      ...> |> CreateProject.validate
      {:error, [{:error, :name, :presence, "must be present"}]}

      iex> nil
      ...> |> CreateProject.new
      ...> |> CreateProject.validate
      ** (RuntimeError) second argument must be a map or keyword list

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
