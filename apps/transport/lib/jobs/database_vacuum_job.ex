defmodule Transport.Jobs.DatabaseVacuumJob do
  @moduledoc """
  Job in charge of running a `VACUUM FULL` on the production database.

  This job is scheduled weekly during Sunday night.
  """
  use Oban.Worker, max_attempts: 3, tags: ["ops"]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Ecto.Adapters.SQL.query!(DB.Repo, "VACUUM FULL")
    :ok
  end
end
