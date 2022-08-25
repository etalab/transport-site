defmodule Transport.Jobs.Backfill.ResourceHistoryResourceIdTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.Backfill.ResourceHistoryResourceId
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "it updates columns" do
    resource_with_datagouv_id = insert(:resource, datagouv_id: Ecto.UUID.generate())
    resource_history = insert(:resource_history, datagouv_id: resource_with_datagouv_id.datagouv_id)
    fake_url = "https://example.com/" <> Ecto.UUID.generate()
    fake_title = "title" <> Ecto.UUID.generate()
    dataset = insert(:dataset)
    resource_with_url = insert(:resource, url: fake_url, dataset: dataset)

    resource_history_with_url =
      insert(:resource_history,
        payload: %{"resource_metadata" => %{"url" => fake_url}, "dataset_id" => resource_with_url.dataset_id}
      )

    resource_with_title = insert(:resource, title: fake_title, dataset: dataset)

    resource_history_with_title =
      insert(:resource_history, payload: %{"title" => fake_title, "dataset_id" => resource_with_url.dataset_id})

    resource_history_orphan = insert(:resource_history)

    assert :ok == perform_job(ResourceHistoryResourceId, %{})

    resource_history = DB.Repo.reload!(resource_history)
    resource_history_with_url = DB.Repo.reload!(resource_history_with_url)
    resource_history_with_title = DB.Repo.reload!(resource_history_with_title)
    resource_history_orphan = DB.Repo.reload!(resource_history_orphan)

    assert resource_with_datagouv_id.id == resource_history.resource_id
    assert resource_with_url.id == resource_history_with_url.resource_id
    assert resource_with_title.id == resource_history_with_title.resource_id
    assert is_nil(resource_history_orphan.resource_id)
  end
end
