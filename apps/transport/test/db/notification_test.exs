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
    other_email = Ecto.UUID.generate() <> "@example.com"
    insert_notification(%{dataset: dataset, reason: :dataset_with_error, email: email})
    insert_notification(%{dataset: dataset, reason: :dataset_with_error, email: email})
    insert_notification(%{dataset: dataset, reason: :dataset_with_error, email: other_email})

    # Can query using the hash column dedicated to search
    rows = DB.Notification |> where([n], n.email_hash == ^email) |> DB.Repo.all()
    assert 2 == Enum.count(rows)

    assert MapSet.new([email]) == rows |> Enum.map(& &1.email) |> MapSet.new()

    # Cannot get rows by using the value, because the encrypted value changes everytime
    assert DB.Notification |> where([n], n.email == ^email) |> DB.Repo.all() |> Enum.empty?()
    # But values are properly decrypted
    assert MapSet.new([email, other_email]) == DB.Notification |> select([n], n.email) |> DB.Repo.all() |> MapSet.new()
  end

  test "can insert without a dataset" do
    DB.Notification.insert!(:periodic_reminder_producers, email = Ecto.UUID.generate() <> "@example.fr")
    assert [%DB.Notification{reason: :periodic_reminder_producers, email: ^email}] = DB.Notification |> DB.Repo.all()
  end

  test "recent_reasons_binned" do
    dataset = insert(:dataset, is_active: true, datagouv_id: Ecto.UUID.generate())
    yesterday = DateTime.add(DateTime.utc_now(), -1, :day)
    email = Ecto.UUID.generate() <> "@example.com"
    other_email = Ecto.UUID.generate() <> "@example.com"

    # Should be ignored, this is an hidden reason
    insert_notification(%{dataset: dataset, reason: :dataset_now_on_nap, email: email})

    insert_notification(%{dataset: dataset, reason: :dataset_with_error, email: email}, %{
      yesterday
      | hour: 10,
        minute: 22
    })

    insert_notification(%{dataset: dataset, reason: :dataset_with_error, email: other_email}, %{
      yesterday
      | hour: 10,
        minute: 22
    })

    insert_notification(%{dataset: dataset, reason: :expiration, email: email}, %{yesterday | hour: 12, minute: 44})

    yesterday_time = fn hour, minute -> %{yesterday | hour: hour, minute: minute, second: 0, microsecond: {0, 6}} end

    assert [
             %{reason: :expiration, timestamp: yesterday_time.(12, 40)},
             %{reason: :dataset_with_error, timestamp: yesterday_time.(10, 20)}
           ] == DB.Notification.recent_reasons_binned(dataset, 7)
  end

  defp insert_notification(%{} = args, %DateTime{} = inserted_at) do
    args |> insert_notification() |> Ecto.Changeset.change(%{inserted_at: inserted_at}) |> DB.Repo.update!()
  end
end
