defmodule Transport.DataValidation.Commands.CreateDataset do
  @moduledoc """
  Command for creating a dataset.

  ## Examples

      iex> %{download_url: "https://link.to/dataset.zip"}
      ...> |> CreateDataset.new
      ...> |> CreateDataset.validate
      {:ok, %CreateDataset{download_url: "https://link.to/dataset.zip"}}

      iex> %{}
      ...> |> CreateDataset.new
      ...> |> CreateDataset.validate
      {:error, [{:error, :download_url, :presence, "must be present"}]}

  """

  defstruct [:download_url]

  use ExConstructor
  use Vex.Struct

  defdelegate validate(struct), to: Vex

  @type t :: %__MODULE__{
          download_url: String.t()
        }

  validates(:download_url, presence: true)
end
