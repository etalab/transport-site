defmodule Transport.Jobs.RefreshAutocompleteJob do
  @moduledoc """
  Job in charge refreshing the view `autocomplete`.

  This is done to avoid a trigger on `dataset`.
  """
  use Oban.Worker, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Ecto.Adapters.SQL.query!(DB.Repo, "REFRESH MATERIALIZED VIEW autocomplete")
    :ok
  end
end
