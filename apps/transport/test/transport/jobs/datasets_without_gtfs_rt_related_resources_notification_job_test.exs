defmodule Transport.Test.Transport.Jobs.DatasetsWithoutGTFSRTRelatedResourcesNotificationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.DatasetsWithoutGTFSRTRelatedResourcesNotificationJob

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "relevant_datasets" do
    # 2 GTFS and 2 GTFS-RT with resource_related set for all GTFS-RT
    %{id: d1_id} = insert(:dataset, is_active: true)
    # 1 GTFS and 1 GTFS-RT
    %{id: d2_id} = insert(:dataset, is_active: true)
    # 2 GTFS and 1 GTFS-RT
    %{id: d3_id} = insert(:dataset, is_active: true)
    gtfs_1_1 = insert(:resource, dataset_id: d1_id, is_community_resource: false, format: "GTFS")
    insert(:resource, dataset_id: d1_id, is_community_resource: false, format: "GTFS")
    gtfs_rt_1 = insert(:resource, dataset_id: d1_id, is_community_resource: false, format: "gtfs-rt")
    gtfs_rt_2 = insert(:resource, dataset_id: d1_id, is_community_resource: false, format: "gtfs-rt")

    insert(:resource, dataset_id: d2_id, is_community_resource: false, format: "GTFS")
    insert(:resource, dataset_id: d2_id, is_community_resource: false, format: "gtfs-rt")

    insert(:resource, dataset_id: d3_id, is_community_resource: false, format: "GTFS")
    insert(:resource, dataset_id: d3_id, is_community_resource: false, format: "GTFS")
    insert(:resource, dataset_id: d3_id, is_community_resource: false, format: "gtfs-rt")

    insert(:resource_related, resource_src: gtfs_rt_1, resource_dst: gtfs_1_1, reason: :gtfs_rt_gtfs)
    insert(:resource_related, resource_src: gtfs_rt_2, resource_dst: gtfs_1_1, reason: :gtfs_rt_gtfs)

    assert [%DB.Dataset{id: ^d3_id}] =
             DatasetsWithoutGTFSRTRelatedResourcesNotificationJob.relevant_datasets() |> Enum.sort()
  end

  test "perform" do
    dataset = insert(:dataset, is_active: true, custom_title: "Super JDD")
    insert(:resource, dataset: dataset, is_community_resource: false, format: "GTFS")
    insert(:resource, dataset: dataset, is_community_resource: false, format: "GTFS")
    insert(:resource, dataset: dataset, is_community_resource: false, format: "gtfs-rt")

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.beta.gouv.fr",
                             "contact@transport.beta.gouv.fr",
                             "contact@transport.beta.gouv.fr",
                             "Jeux de données GTFS-RT sans ressources liées" = _subject,
                             plain_text_body,
                             "" = _html_part ->
      assert plain_text_body =~ ~r/des liens entre les ressources GTFS-RT et GTFS sont manquants/
      assert plain_text_body =~ ~r/Super JDD/
      :ok
    end)

    assert :ok == perform_job(DatasetsWithoutGTFSRTRelatedResourcesNotificationJob, %{})
  end
end
