defmodule Transport.Jobs.IRVESimpleConsolidationJob do
  @moduledoc """
  Nightly production of IRVE "simple" consolidation (writing pdc to DB).
  """
  use Oban.Worker, unique: [period: {1, :days}], tags: ["irve"], max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting IRVE Simple Consolidation Job")

    Transport.IRVE.SimpleConsolidation.process()
  end
end
