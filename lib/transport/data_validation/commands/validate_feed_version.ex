defmodule Transport.DataValidation.Commands.ValidateFeedVersion do
  @moduledoc """
  Command for validating a feed version.

  ## Examples

      iex> %{id: "1"}
      ...> |> ValidateFeedVersion.new
      ...> |> ValidateFeedVersion.validate
      {:ok, %ValidateFeedVersion{id: "1"}}

      iex> %{id: "1", format: "netex"}
      ...> |> ValidateFeedVersion.new
      ...> |> ValidateFeedVersion.validate
      {:ok, %ValidateFeedVersion{id: "1"}}

      iex> %{}
      ...> |> ValidateFeedVersion.new
      ...> |> ValidateFeedVersion.validate
      {:error, [{:error, :id, :presence, "must be present"}]}

  """

  defstruct [:id]

  use ExConstructor
  use Vex.Struct

  defdelegate validate(struct), to: Vex

  @type t :: %__MODULE__{
    id: String.t
  }

  validates :id, presence: true
end
