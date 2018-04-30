defmodule Transport.DataValidation.Events.DatasetCreated do
  @moduledoc """
  Event for a created dataset.

  ## Examples

      iex> DatasetCreated.new(%{download_url: "https://link.to/dataset.zip"})
      %DatasetCreated{download_url: "https://link.to/dataset.zip"}

  """

  defstruct [:download_url]

  use ExConstructor

  @type t :: %__MODULE__{
          download_url: String.t()
        }
end
