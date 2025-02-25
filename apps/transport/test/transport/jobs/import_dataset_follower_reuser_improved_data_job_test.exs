defmodule Transport.Test.Transport.Jobs.ImportDatasetFollowerReuserImprovedDataJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Ecto.Query
  import Transport.Jobs.ImportDatasetFollowerReuserImprovedDataJob
  alias Transport.Jobs.ImportDatasetFollowerReuserImprovedDataJob

  @dataset_custom_tag "repartage_donnees"
  @google_maps_org_id "63fdfe4f4cd1c437ac478323"
  @transit_org_id "5c9a6477634f4133c7a5fc01"

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "perform" do
    random_contact = insert_contact()
    google_maps_org = insert(:organization, id: @google_maps_org_id)

    google_maps_contact =
      insert_contact(%{
        datagouv_user_id: Ecto.UUID.generate(),
        organizations: [google_maps_org |> Map.from_struct()]
      })

    transit_org = insert(:organization, id: @transit_org_id)

    transit_contact =
      insert_contact(%{
        datagouv_user_id: Ecto.UUID.generate(),
        organizations: [transit_org |> Map.from_struct()]
      })

    eligible_dataset = insert(:dataset, custom_tags: [@dataset_custom_tag], type: "public-transit")
    other_eligible_dataset = insert(:dataset, custom_tags: [@dataset_custom_tag], type: "public-transit")
    random_dataset = insert(:dataset)

    insert(:dataset_follower, contact: transit_contact, dataset: eligible_dataset, source: :follow_button)
    insert(:dataset_follower, contact: transit_contact, dataset: random_dataset, source: :follow_button)

    assert MapSet.new([eligible_dataset.id, other_eligible_dataset.id]) == relevant_dataset_ids() |> MapSet.new()

    assert MapSet.new([google_maps_contact.id, transit_contact.id]) ==
             relevant_contacts() |> Enum.map(& &1.id) |> MapSet.new()

    assert 0 ==
             DB.DatasetFollower.base_query()
             |> where([dataset_follower: df], df.source == :improved_data_pilot)
             |> DB.Repo.aggregate(:count)

    assert :ok == perform_job(ImportDatasetFollowerReuserImprovedDataJob, %{})

    # `random_contact` has no favorites
    # `google_maps_contact` had 0 and now follows eligible datasets
    # `transit_contact` followed a random dataset and an eligible one, the other eligible dataset has been added
    assert MapSet.new([]) == followed_dataset_ids(random_contact)
    assert MapSet.new([eligible_dataset.id, other_eligible_dataset.id]) == followed_dataset_ids(google_maps_contact)

    assert MapSet.new([eligible_dataset.id, other_eligible_dataset.id, random_dataset.id]) ==
             followed_dataset_ids(transit_contact)

    assert 3 ==
             DB.DatasetFollower.base_query()
             |> where([dataset_follower: df], df.source == :improved_data_pilot)
             |> DB.Repo.aggregate(:count)

    # Can run the job again without problems, existing favorites are ignored
    assert :ok == perform_job(ImportDatasetFollowerReuserImprovedDataJob, %{})
  end

  test "dataset custom tag has the right value" do
    assert @dataset_custom_tag == Application.fetch_env!(:transport, :data_sharing_pilot_dataset_custom_tag)
  end

  defp followed_dataset_ids(%DB.Contact{} = contact) do
    contact
    |> DB.Repo.preload(:followed_datasets)
    |> Map.fetch!(:followed_datasets)
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end
end
