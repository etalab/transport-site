defmodule Transport.DataValidation.Queries.FindDataset do
  @moduledoc """
  Query for finding a dataset.

  ## Examples

      iex> FindDataset.new(%{download_url: "https://link.to/dataset.zip"})
      %FindDataset{download_url: "https://link.to/dataset.zip"}

  """

  defstruct [:download_url]

  use ExConstructor

  @type t :: %__MODULE__{
          download_url: String.t()
        }
end
