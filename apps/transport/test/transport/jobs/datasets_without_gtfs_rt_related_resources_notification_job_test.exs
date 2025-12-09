defmodule Transport.Test.Transport.Jobs.DatasetsWithoutGTFSRTRelatedResourcesNotificationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Swoosh.TestAssertions
  alias Transport.Jobs.DatasetsWithoutGTFSRTRelatedResourcesNotificationJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    on_exit(fn -> assert_no_email_sent() end)
  end

  test "relevant_datasets" do
    # 2 GTFS and 2 GTFS-RT with resource_related set for all GTFS-RT
    %{dataset: %DB.Dataset{id: d1_id} = d1, resource: %DB.Resource{format: "GTFS"} = gtfs_1_1} =
      insert_up_to_date_resource_and_friends()

    insert_up_to_date_resource_and_friends(dataset: d1)
    gtfs_rt_1 = insert(:resource, dataset_id: d1_id, is_community_resource: false, format: "gtfs-rt")
    gtfs_rt_2 = insert(:resource, dataset_id: d1_id, is_community_resource: false, format: "gtfs-rt")

    insert(:resource_related, resource_src: gtfs_rt_1, resource_dst: gtfs_1_1, reason: :gtfs_rt_gtfs)
    insert(:resource_related, resource_src: gtfs_rt_2, resource_dst: gtfs_1_1, reason: :gtfs_rt_gtfs)

    # 1 GTFS and 1 GTFS-RT
    %{dataset: %DB.Dataset{id: d2_id}, resource: %DB.Resource{format: "GTFS"}} =
      insert_up_to_date_resource_and_friends()

    insert(:resource, dataset_id: d2_id, is_community_resource: false, format: "gtfs-rt")

    # 1 up-to-date GTFS, 1 outdated GTFS and 1 GTFS-RT
    %{dataset: %DB.Dataset{id: d3_id} = d3, resource: %DB.Resource{format: "GTFS"}} =
      insert_up_to_date_resource_and_friends()

    insert_outdated_resource_and_friends(dataset: d3)
    insert(:resource, dataset_id: d3_id, is_community_resource: false, format: "gtfs-rt")

    # 2 GTFS and 1 GTFS-RT, without resource_related set
    %{dataset: %DB.Dataset{id: d4_id} = d4, resource: %DB.Resource{format: "GTFS"}} =
      insert_up_to_date_resource_and_friends()

    insert_up_to_date_resource_and_friends(dataset: d4)
    insert(:resource, dataset_id: d4_id, is_community_resource: false, format: "gtfs-rt")

    assert [%DB.Dataset{id: ^d4_id}] =
             DatasetsWithoutGTFSRTRelatedResourcesNotificationJob.relevant_datasets() |> Enum.sort()
  end

  test "perform" do
    %{dataset: %DB.Dataset{id: dataset_id, slug: slug} = dataset, resource: %DB.Resource{format: "GTFS"}} =
      insert_up_to_date_resource_and_friends(custom_title: "Super JDD")

    insert_up_to_date_resource_and_friends(dataset: dataset)
    insert(:resource, dataset: dataset, is_community_resource: false, format: "gtfs-rt")

    assert [%DB.Dataset{id: ^dataset_id}] = DatasetsWithoutGTFSRTRelatedResourcesNotificationJob.relevant_datasets()

    assert :ok == perform_job(DatasetsWithoutGTFSRTRelatedResourcesNotificationJob, %{})

    assert_email_sent(fn %Swoosh.Email{
                           from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                           to: [{"", "contact@transport.data.gouv.fr"}],
                           reply_to: {"", "contact@transport.data.gouv.fr"},
                           subject: "Jeux de données GTFS-RT sans ressources liées",
                           text_body: nil,
                           html_body: html_body
                         } ->
      assert html_body =~ ~r/des liens entre les ressources GTFS-RT et GTFS sont manquants/
      assert html_body =~ ~r|<a href="http://127.0.0.1:5100/datasets/#{slug}">Super JDD</a>|
    end)
  end
end
