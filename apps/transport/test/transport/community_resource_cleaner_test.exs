defmodule Transport.CommunityResourcesCleanerTest do
  use ExUnit.Case
  import TransportWeb.Factory
  import Transport.CommunityResourcesCleaner
  alias DB.Repo

  @transport_publisher_label Application.get_env(:transport, :datagouvfr_transport_publisher_label)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  defp insert_dataset_associated_with_ressources(resources) do
    :dataset
    |> insert()
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
    resource_parent =
      insert(:resource, %{
        is_community_resource: false,
        url: "original_url"
      })

    community_resource =
      insert(:resource, %{
        is_community_resource: true,
        community_resource_publisher: @transport_publisher_label,
        original_resource_url: "original_url"
      })

    insert_dataset_associated_with_ressources([resource_parent, community_resource])

    # community_resource is not an orphan
    assert [] == list_orphan_community_resources()

    # now delete the parent
    Repo.delete!(resource_parent)

    # the community resource is now an orphan
    assert [community_resource.id] == list_orphan_community_resources()
  end

  test "orphan detection with 2 datasets" do
    resource1 =
      insert(:resource, %{
        is_community_resource: true,
        community_resource_publisher: @transport_publisher_label,
        original_resource_url: "original_url1"
      })

    resource2 =
      insert(:resource, %{
        is_community_resource: true,
        community_resource_publisher: @transport_publisher_label,
        original_resource_url: "original_url2"
      })

    insert_dataset_associated_with_ressources([resource1])
    insert_dataset_associated_with_ressources([resource2])

    resources = list_orphan_community_resources()

    assert Enum.count(resources) == 2
    assert Enum.member?(resources, resource1.id) and Enum.member?(resources, resource2.id)
  end
end
