defmodule Transport.Jobs.NewDatasetJob do
  @moduledoc """
  Job dispatched when a dataset is created from the backoffice.
  """
  use Oban.Worker, max_attempts: 3, unique: [period: :infinity]

  @impl true
  def perform(%{args: %{"dataset_id" => dataset_id}}) do
    DB.Dataset
    |> DB.Repo.get!(dataset_id)
    |> Transport.DataChecker.send_new_dataset_notifications()
  end
end
