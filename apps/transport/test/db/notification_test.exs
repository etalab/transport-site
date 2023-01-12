defmodule DB.NotificationTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Ecto.Query

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "can save objects" do
    dataset = insert(:dataset, is_active: true, datagouv_id: Ecto.UUID.generate())

    email = "foo@example.fr"
    insert_notification(%{dataset_id: dataset.id, reason: :dataset_with_error, email: email})
    insert_notification(%{dataset_id: dataset.id, reason: :dataset_with_error, email: email})

    # Can query using the hash column dedicated to search
    rows = DB.Notification |> where([n], n.email_hash == ^email) |> DB.Repo.all()
    assert 2 == Enum.count(rows)

    assert MapSet.new([email]) == rows |> Enum.map(& &1.email) |> MapSet.new()

    # Cannot get rows by using the value, because the encrypted value changes everytime
    assert DB.Notification |> where([n], n.email == ^email) |> DB.Repo.all() |> Enum.empty?()
  end
end
