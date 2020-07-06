defmodule Transport.LogCleaner do
  @moduledoc """
  Clean the old logs_import and logs_validation
  """
  alias DB.{LogsImport, LogsValidation, Repo}
  import Ecto.Query
  require Logger

  @nb_days_to_keep 31

  def clean_old_logs do
    limit =
      DateTime.utc_now()
      |> DateTime.add(-1 * 24 * 3600 * @nb_days_to_keep, :second)
      |> DateTime.truncate(:second)

    nb_validations_before = count_logs_validation()
    nb_import_before = count_logs_import()
    Logger.info("cleaning old logs older than #{limit}.")
    Logger.info("There are #{nb_import_before} import logs and #{nb_validations_before} validation logs")

    LogsValidation
    |> where([l], l.timestamp < ^limit)
    |> Repo.delete_all()

    LogsImport
    |> where([l], l.timestamp < ^limit)
    |> Repo.delete_all()

    Logger.info("cleaned #{nb_import_before - count_logs_import()} import logs \
and #{nb_validations_before - count_logs_validation()} validation logs")
  end

  defp count_logs_validation, do: Repo.aggregate(LogsValidation, :count, :id)

  defp count_logs_import, do: Repo.aggregate(LogsImport, :count, :id)
end
