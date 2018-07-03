defmodule Transport.DataValidation.Commands.ValidateDataset do
  @moduledoc """
  Command for validating a dataset.

  ## Examples

      iex> %{uuid: "1", download_url: "https://data.portal/gtfs.zip"}
      ...> |> Dataset.new
      ...> |> ValidateDataset.new
      ...> |> ValidateDataset.validate
      {:ok, %ValidateDataset{uuid: "1", download_url: "https://data.portal/gtfs.zip"}}

      iex> %{download_url: "https://data.portal/gtfs.zip"}
      ...> |> Dataset.new
      ...> |> ValidateDataset.new
      ...> |> ValidateDataset.validate
      {:error, [{:error, :uuid, :presence, "must be present"}]}

      iex> %{uuid: "1"}
      ...> |> Dataset.new
      ...> |> ValidateDataset.new
      ...> |> ValidateDataset.validate
      {:error, [{:error, :download_url, :presence, "must be present"}]}

  """

  defstruct [:uuid, :download_url]

  use ExConstructor
  use Vex.Struct

  defdelegate validate(struct), to: Vex

  @type t :: %__MODULE__{
          uuid: String.t(),
          download_url: String.t()
        }

  validates(:uuid, presence: true)
  validates(:download_url, presence: true)
end
