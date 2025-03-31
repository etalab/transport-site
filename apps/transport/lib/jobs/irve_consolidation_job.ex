defmodule Transport.Jobs.IRVEConsolidationJob do
  @moduledoc """
  Nightly production of IRVE consolidation.
  """
  use Oban.Worker, unique: [period: {1, :days}], tags: ["irve"], max_attempts: 3
  require Logger
  import Transport.S3.AggregatesUploader

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    IO.puts("My life is chugging along nicely.")
  end
end
