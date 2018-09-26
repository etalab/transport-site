defmodule Transport.DataValidation.Events.DatasetUpdated do
  @moduledoc """
  Event for an updated dataset.

  ## Examples

      iex> DatasetUpdated.new(%{download_url: "https://link.to/dataset.zip", validations: []})
      %DatasetUpdated{download_url: "https://link.to/dataset.zip", validations: []}

  """

  defstruct [:download_url, :validations]

  use ExConstructor

  @type t :: %__MODULE__{
          download_url: String.t(),
          validations: Map.t(),
        }
end
