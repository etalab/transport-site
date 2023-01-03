defmodule Transport.LogCleaner do
  @moduledoc """
  Clean the old logs_import and logs_validation
  """
  alias DB.{LogsImport, Repo}
  import Ecto.Query
  require Logger

  @nb_days_to_keep 31

  def clean_old_logs do
    limit =
      DateTime.utc_now()
      |> DateTime.add(-1 * 24 * 3600 * @nb_days_to_keep, :second)
      |> DateTime.truncate(:second)

    nb_import_before = count_logs_import()
    Logger.info("cleaning old logs older than #{limit}.")
    Logger.info("There are #{nb_import_before} import logs")

    LogsImport
    |> where([l], l.timestamp < ^limit)
    |> Repo.delete_all()

    Logger.info("cleaned #{nb_import_before - count_logs_import()} import logs")
  end

  defp count_logs_import, do: Repo.aggregate(LogsImport, :count, :id)
end
