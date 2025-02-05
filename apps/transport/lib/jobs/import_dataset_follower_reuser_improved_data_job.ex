defmodule Transport.Jobs.ImportDatasetFollowerReuserImprovedDataJob do
  @moduledoc """
  As part of the reuser improved data pilot, this job adds specific datasets
  to the favorites list for users in participating organizations.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    dataset_ids_to_follow = relevant_dataset_ids()

    Enum.each(relevant_contacts(), fn %DB.Contact{followed_datasets: followed_datasets} = contact ->
      followed_dataset_ids = Enum.map(followed_datasets, & &1.id)

      dataset_ids_to_follow
      |> Enum.reject(&(&1 in followed_dataset_ids))
      |> Enum.each(fn dataset_id ->
        DB.DatasetFollower.follow!(contact, %DB.Dataset{id: dataset_id}, source: :improved_data_pilot)
      end)
    end)
  end

  def relevant_contacts do
    dataset_query = from(d in DB.Dataset, select: [:id])
    org_ids = Application.fetch_env!(:transport, :data_sharing_pilot_eligible_datagouv_organization_ids)

    DB.Contact.base_query()
    |> preload(followed_datasets: ^dataset_query)
    |> join(:inner, [contact: c], o in assoc(c, :organizations), as: :organization)
    |> where([organization: o], o.id in ^org_ids)
    |> select([contact: c], c)
    |> DB.Repo.all()
  end

  def relevant_dataset_ids do
    DB.Dataset.base_query()
    |> where([dataset: d], d.type == "public-transit")
    |> DB.Dataset.filter_by_custom_tag(Application.fetch_env!(:transport, :data_sharing_pilot_dataset_custom_tag))
    |> select([dataset: d], d.id)
    |> DB.Repo.all()
  end
end
