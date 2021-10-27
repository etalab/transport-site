defmodule Transport.Scheduler do
  @moduledoc """
  This made to launch schedule tasks
  """

  use Quantum,
    otp_app: :transport

  def scheduled_jobs do
    [
      # Every day at 4am UTC
      {"0 4 * * *", {Transport.ImportData, :import_validate_all, []}},
      # Send email for outdated data
      {"@daily", {Transport.DataChecker, :outdated_data, []}},
      # Set inactive data
      {"@daily", {Transport.DataChecker, :inactive_data, []}},
      # Watch for new comments on datasets
      {"@daily", {Transport.CommentsChecker, :check_for_new_comments, []}},
      # Delete orphan community resources
      {"@daily", {Transport.CommunityResourcesCleaner, :clean_community_resources, []}},
      # backup all resources
      {"@daily", {Transport.History.Backup, :backup_resources, []}},
      # clean old logs
      {"0 3 * * *", {Transport.LogCleaner, :clean_old_logs, []}},
      # clean old validations
      {"0 2 * * *", {Transport.ValidationCleaner, :clean_old_validations, []}},
      # compute some global stats and store them in the DB
      {"0 20 * * *", {Transport.StatsHandler, :store_stats, []}},
      # generate NeTEx / geojson files for all GTFS.
      # Note : this should be run before the import_validate_all for the NeTEx / geojson
      # to be created when the import is run
      {"0 1 * * *", {Transport.GtfsConversions, :convert_all, []}},
      {"0 * * * *", {Transport.ImportData, :refresh_places, []}}
    ]
  end
end
