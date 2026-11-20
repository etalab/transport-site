defmodule Transport.Jobs.IRVEConsolidationJob do
  @moduledoc """
  Nightly production of IRVE consolidation (writing pdc to DB).

  The optional `"unlisted_grace_period_days"` arg overrides the grace period before the PDCs of resources
  no longer on data.gouv.fr leave the deduplicated file (0 soft-deletes them right away).
  """
  use Oban.Worker, unique: [period: {1, :days}], tags: ["irve"], max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("Starting IRVE Consolidation Job")

    Transport.IRVE.Consolidation.process(unlisted_grace_period_days: args["unlisted_grace_period_days"])
  end
end
