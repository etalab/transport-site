defmodule Transport.Jobs.StopsRegistrySnapshotJob do
  @moduledoc """
  Job in charge of building a snapshot of the stops registry.
  """

  use Oban.Worker, unique: [period: {1, :days}], tags: ["registry"], max_attempts: 3
  require Logger

  @impl Oban.Worker
  def perform(_job) do
    file = "#{System.tmp_dir!()}/registre-arrets.csv"

    Transport.Registry.Engine.execute(file)
  end
end
