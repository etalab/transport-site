defmodule Transport.Jobs.IRVEConsolidationJob do
  @moduledoc """
  Nightly production of IRVE consolidation (writing pdc to DB).
  """
  use Oban.Worker, unique: [period: {1, :days}], tags: ["irve"], max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting IRVE Consolidation Job")

    Transport.IRVE.Consolidation.process()
  end
end
