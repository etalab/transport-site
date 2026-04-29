defmodule Transport.QuantumScheduler do
  @moduledoc """
  In-memory cron scheduler (Quantum) for jobs that don't need DB-backed
  scheduling (no retries, no persistence, no UI). Coexists with Oban Cron
  (`config/runtime.exs`) which handles jobs needing those features.
  """

  use Quantum,
    otp_app: :transport

  @doc """
  The jobs are defined here, but only programmatically activated on one node. See `config/runtime.exs`.

  Tasks use `&Mod.fun/0` captures rather than `{Mod, :fun, []}` tuples to get compile-time
  checking of the references (e.g. catch #5046).
  """
  def scheduled_jobs do
    [
      # Every day at 4am UTC
      {"0 4 * * *", &Transport.ImportData.import_validate_all/0},
      # Set inactive data
      {"@daily", &Transport.DataChecker.inactive_data/0},
      # Watch for new comments on datasets
      {"@daily", &Transport.CommentsChecker.check_for_new_comments/0},
      # clean old logs
      {"0 3 * * *", &Transport.LogCleaner.clean_old_logs/0},
      # compute some global stats and store them in the DB
      {"0 20 * * *", &Transport.StatsHandler.store_stats/0},
      # Duplicate `Transport.Jobs.RefreshAutocompleteJob` (Oban, see #5114). Kept for now.
      {"0 * * * *", &Transport.ImportData.refresh_autocomplete/0}
    ]
  end
end
