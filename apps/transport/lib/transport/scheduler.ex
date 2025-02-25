defmodule Transport.Scheduler do
  @moduledoc """
  This made to launch schedule tasks
  """

  use Quantum,
    otp_app: :transport

  @doc """
  The jobs are defined here, but only programmatically activated on one node. See `config/runtime.exs`.
  """
  def scheduled_jobs do
    [
      # Every day at 4am UTC
      {"0 4 * * *", {Transport.ImportData, :import_validate_all, []}},
      # Set inactive data
      {"@daily", {Transport.DataChecker, :inactive_data, []}},
      # Watch for new comments on datasets
      {"@daily", {Transport.CommentsChecker, :check_for_new_comments, []}},
      # clean old logs
      {"0 3 * * *", {Transport.LogCleaner, :clean_old_logs, []}},
      # compute some global stats and store them in the DB
      {"0 20 * * *", {Transport.StatsHandler, :store_stats, []}},
      {"0 * * * *", {Transport.ImportData, :refresh_places, []}}
    ]
  end
end
