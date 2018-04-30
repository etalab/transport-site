defmodule Transport.DataValidation.Events.DatasetValidated do
  @moduledoc """
  Event for a validated dataset.

  ## Examples

      iex> DatasetValidated.new(%{uuid: "1", download_url: "https://link.to/dataset.zip"})
      %DatasetValidated{uuid: "1", download_url: "https://link.to/dataset.zip"}

  """

  defstruct [:uuid, :download_url]

  use ExConstructor

  @type t :: %__MODULE__{
          uuid: String.t(),
          download_url: String.t()
        }
end
