defmodule Transport.Test.Transport.Jobs.DatasetHistoryJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  use Oban.Testing, repo: DB.Repo
  import Ecto.Query

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "historize a dataset" do
    dataset =
      insert(:dataset,
        datagouv_id: datagouv_id = Ecto.UUID.generate(),
        licence: "love",
        type: "public-transport",
        slug: "the-slug"
      )

    # a resource with multiple resource history
    r1 = insert(:resource, dataset_id: dataset.id, url: "url1")
    insert(:resource_history, resource_id: r1.id)
    %{id: rh_id_latest} = insert(:resource_history, resource_id: r1.id)

    # a resource with multiple resource metadata
    r2 = insert(:resource, dataset_id: dataset.id, url: "url2")
    insert(:resource_metadata, resource_id: r2.id)
    %{id: rm_id_latest} = insert(:resource_metadata, resource_id: r2.id)

    # just a resource
    r3 = insert(:resource, dataset_id: dataset.id, url: "url3")

    :ok = perform_job(Transport.Jobs.DatasetHistoryJob, %{"dataset_id" => dataset.id})

    [dataset_history] = DB.DatasetHistory |> preload(:dataset_history_resources) |> DB.Repo.all()

    dataset_id = dataset.id

    assert %{
             dataset_id: ^dataset_id,
             dataset_datagouv_id: ^datagouv_id,
             payload: %{"licence" => "love", "type" => "public-transport", "slug" => "the-slug"}
           } = dataset_history

    dataset_history_resources = dataset_history.dataset_history_resources

    assert Enum.count(dataset_history_resources) == 3

    dhr1 = dataset_history_resources |> Enum.find(&(&1.resource_id == r1.id))
    assert %{resource_history_id: ^rh_id_latest, resource_metadata_id: nil, payload: %{"url" => "url1"}} = dhr1

    dhr2 = dataset_history_resources |> Enum.find(&(&1.resource_id == r2.id))
    assert %{resource_history_id: nil, resource_metadata_id: ^rm_id_latest, payload: %{"url" => "url2"}} = dhr2

    dhr3 = dataset_history_resources |> Enum.find(&(&1.resource_id == r3.id))
    assert %{resource_history_id: nil, resource_metadata_id: nil, payload: %{"url" => "url3"}} = dhr3
  end
end
