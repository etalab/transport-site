defmodule Transport.Jobs.NewDatasetNotificationsJob do
  @moduledoc """
  Job in charge of sending notifications about datasets that have been added recently.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{inserted_at: %DateTime{} = inserted_at}) do
    inserted_at |> relevant_datasets() |> Transport.DataChecker.send_new_dataset_notifications()
    :ok
  end

  def relevant_datasets(%DateTime{} = inserted_at) do
    datetime_limit = inserted_at |> DateTime.add(-1, :day)

    DB.Dataset.base_query()
    |> where([dataset: d], d.inserted_at >= ^datetime_limit)
    |> DB.Repo.all()
  end
end
