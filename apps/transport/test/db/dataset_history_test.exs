defmodule DB.DatasetHistoryTest do
  use ExUnit.Case, async: true
  import DB.DatasetHistory
  import DB.Factory

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "from_old_dataset_slug" do
    test "it finds the current dataset when given an old slug" do
      %{id: dataset_id} =
        dataset = insert(:dataset, datagouv_id: Ecto.UUID.generate(), is_active: true, slug: Ecto.UUID.generate())

      insert(:dataset_history, dataset_id: dataset.id, payload: %{slug: old_slug = Ecto.UUID.generate()})
      insert(:dataset_history, dataset_id: dataset.id, payload: %{slug: other_old_slug = Ecto.UUID.generate()})
      assert %DB.DatasetHistory{dataset_id: ^dataset_id} = from_old_dataset_slug(old_slug)
      assert %DB.DatasetHistory{dataset_id: ^dataset_id} = from_old_dataset_slug(other_old_slug)
      assert nil == from_old_dataset_slug(dataset.slug)
    end

    test "it raises when there are multiple results" do
      dataset = insert(:dataset, datagouv_id: Ecto.UUID.generate(), is_active: true, slug: Ecto.UUID.generate())
      dataset2 = insert(:dataset, datagouv_id: Ecto.UUID.generate(), is_active: true, slug: Ecto.UUID.generate())
      old_slug = Ecto.UUID.generate()
      insert(:dataset_history, dataset_id: dataset.id, payload: %{slug: old_slug})
      insert(:dataset_history, dataset_id: dataset2.id, payload: %{slug: old_slug})

      assert_raise Ecto.MultipleResultsError, fn ->
        from_old_dataset_slug(old_slug)
      end
    end

    test "it works with inactive datasets" do
      %{id: dataset_id} =
        dataset = insert(:dataset, datagouv_id: Ecto.UUID.generate(), is_active: false, slug: Ecto.UUID.generate())

      refute dataset.is_active
      insert(:dataset_history, dataset_id: dataset.id, payload: %{slug: old_slug = Ecto.UUID.generate()})

      assert %DB.DatasetHistory{dataset_id: ^dataset_id} = from_old_dataset_slug(old_slug)
    end
  end
end
