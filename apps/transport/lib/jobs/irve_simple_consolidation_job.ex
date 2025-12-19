defmodule Transport.Jobs.IRVESimpleConsolidationJob do
  @moduledoc """
  Nightly production of IRVE "simple" consolidation (writing pdc to DB).
  """
  use Oban.Worker, unique: [period: {1, :days}], tags: ["irve"], max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Transport.IRVE.SimpleConsolidation.process()
  end
end
