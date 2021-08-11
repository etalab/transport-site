defmodule Transport.CommunityResourcesCleanerTest do
  use ExUnit.Case, async: false
  import TransportWeb.Factory
  import Transport.CommunityResourcesCleaner
  alias DB.Repo

  setup do
    Mox.stub_with(
      Datagouvfr.Client.CommunityResources.Mock,
      Datagouvfr.Client.StubCommunityResources
    )

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  defp insert_dataset_associated_with_ressources(resources, datagouv_id \\ nil) do
    :dataset
    |> insert(%{datagouv_id: datagouv_id})
    |> Repo.preload(:resources)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:resources, resources)
    |> Repo.update!()
  end

  test "community resources published by someone else are ignored" do
    resource =
      insert(:resource, %{
        community_resource_publisher: "un autre producteur",
        is_community_resource: true,
        original_resource_url: "original_url"
      })

    insert_dataset_associated_with_ressources([resource])
    assert [] == list_orphan_community_resources()
  end

  test "what happens when a community resource becomes an orphan" do
    resource_datagouv_id = "r1"
    dataset_datagouv_id = "d1"

    resource_parent =
      insert(:resource, %{
        is_community_resource: false,
        url: "original_url"
      })

    community_resource =
      insert(:resource, %{
        is_community_resource: true,
        community_resource_publisher: transport_publisher_label(),
        original_resource_url: "original_url",
        datagouv_id: resource_datagouv_id
      })

    dataset =
      insert_dataset_associated_with_ressources(
        [resource_parent, community_resource],
        dataset_datagouv_id
      )

    # community_resource is not an orphan
    assert [] == list_orphan_community_resources()

    # now delete the parent
    Repo.delete!(resource_parent)

    # the community resource is now an orphan
    assert [
             %{
               dataset_datagouv_id: dataset_datagouv_id,
               resource_datagouv_id: resource_datagouv_id,
               dataset_id: dataset.id,
               resource_id: community_resource.id
             }
           ] == list_orphan_community_resources()
  end

  test "orphan detection with 2 datasets" do
    resource1 =
      insert(:resource, %{
        is_community_resource: true,
        community_resource_publisher: transport_publisher_label(),
        original_resource_url: "original_url1"
      })

    resource2 =
      insert(:resource, %{
        is_community_resource: true,
        community_resource_publisher: transport_publisher_label(),
        original_resource_url: "original_url2"
      })

    insert_dataset_associated_with_ressources([resource1])
    insert_dataset_associated_with_ressources([resource2])

    resources = list_orphan_community_resources() |> Enum.map(& &1.resource_id)

    assert Enum.count(resources) == 2
    assert Enum.member?(resources, resource1.id) and Enum.member?(resources, resource2.id)
  end

  test "clean 2 orphan resources" do
    # not an orphan of transport.data.gouv
    resource10 =
      insert(:resource, %{
        is_community_resource: true,
        community_resource_publisher: "someone else",
        original_resource_url: "original_url10"
      })

    # orphan 1
    resource11 =
      insert(:resource, %{
        is_community_resource: true,
        community_resource_publisher: transport_publisher_label(),
        original_resource_url: "original_url11"
      })

    insert_dataset_associated_with_ressources([resource10, resource11])

    # orphan 2
    resource20 =
      insert(:resource, %{
        is_community_resource: true,
        community_resource_publisher: transport_publisher_label(),
        original_resource_url: "original_url20"
      })

    insert_dataset_associated_with_ressources([resource20])

    assert {:ok, 2} == clean_community_resources()
  end
end
