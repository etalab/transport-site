defmodule Transport.DataValidation.Events.DatasetValidated do
  @moduledoc """
  Event for a validated dataset.

  ## Examples

      iex> DatasetValidated.new(%{download_url: "https://link.to/dataset.zip"})
      %DatasetValidated{download_url: "https://link.to/dataset.zip"}

  """

  defstruct [:download_url]

  use ExConstructor

  @type t :: %__MODULE__{
          download_url: String.t()
        }
end
