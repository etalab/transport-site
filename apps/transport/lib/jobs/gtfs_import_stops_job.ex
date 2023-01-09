defmodule Transport.Jobs.GTFSImportStopsJob do
  use Oban.Worker, max_attempts: 1
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    :ok
  end
end
