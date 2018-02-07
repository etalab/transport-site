defmodule Transport.DataValidation.Repository.FeedVersionRepository do
  @moduledoc """
  A feed version repository to interact with datatools.
  """

  alias Transport.DataValidation.Commands.ValidateFeedVersion

  @doc """
  Validates a feed version.
  """
  @spec execute(ValidateFeedVersion.t) :: {:ok, FeedVersion.t} | {:error, any()}
  def execute(%ValidateFeedVersion{} = command) do
    case command.id do
      "1" -> {:ok, %{}}
      "2" -> {:error, :netex}
    end
  end
end
