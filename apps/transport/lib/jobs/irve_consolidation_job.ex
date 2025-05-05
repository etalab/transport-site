defmodule Transport.Jobs.IRVEConsolidationJob do
  @moduledoc """
  Nightly production of IRVE consolidation.
  """
  use Oban.Worker, unique: [period: {1, :days}], tags: ["irve"], max_attempts: 3
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Transport.IRVE.Consolidation.build_aggregate_and_report!()
  end
end
