defmodule Transport.ValidationCleaner do
  @moduledoc """
  Clean the old hand made validations (not related to one of our resource)
  """
  alias DB.{Repo, Validation}
  import Ecto.Query
  require Logger

  def clean_old_validations do
    nb_days_to_keep = Application.fetch_env!(:transport, :nb_days_to_keep_validations)

    limit =
      DateTime.utc_now()
      |> DateTime.add(-1 * 24 * 3600 * nb_days_to_keep, :second)
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()

    nb_validations_before = count_validations()
    Logger.info("cleaning old validations older than #{limit}.")
    Logger.info("There are #{nb_validations_before} validation not linked to a resource")

    Validation
    |> where([v], is_nil(v.resource_id))
    |> where([v], v.date < ^limit)
    |> Repo.delete_all()

    Logger.info("cleaned #{nb_validations_before - count_validations()} validation without a resource")
  end

  defp count_validations,
    do:
      Validation
      |> where([v], is_nil(v.resource_id))
      |> Repo.aggregate(:count, :id)
end
