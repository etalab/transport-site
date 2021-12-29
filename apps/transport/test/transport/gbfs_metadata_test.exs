defmodule Transport.GBFSMetadataTest do
  use ExUnit.Case, async: true
  use TransportWeb.DatabaseCase, cleanup: []
  import DB.Factory
  import Mox
  alias DB.{Repo, Resource}
  import Transport.GBFSMetadata, only: [set_gbfs_feeds_metadata: 0]

  @gbfs_url "https://example.com/gbfs.json"

  setup :verify_on_exit!

  test "set_gbfs_feeds_metadata" do
    %{id: resource_id} =
      Repo.insert!(%Resource{
        url: @gbfs_url,
        datagouv_id: "r1",
        dataset: insert(:dataset, is_active: true, type: "bike-scooter-sharing", aom: nil)
      })

    Transport.Shared.GBFSMetadata.Mock
    |> expect(:compute_feed_metadata, 1, fn url, cors_base_url ->
      assert url == @gbfs_url
      assert cors_base_url == TransportWeb.Endpoint.url()
      %{"foo" => "bar"}
    end)

    assert :ok == set_gbfs_feeds_metadata()

    resource = Resource |> where([r], r.id == ^resource_id) |> Repo.one!()

    assert %{format: "gbfs", metadata: %{"foo" => "bar"}} = resource
  end
end
