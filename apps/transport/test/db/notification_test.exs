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
    insert_notification(%{dataset: dataset, role: :producer, reason: :dataset_with_error, email: email})
    insert_notification(%{dataset: dataset, role: :producer, reason: :dataset_with_error, email: email})
    insert_notification(%{dataset: dataset, role: :producer, reason: :dataset_with_error, email: other_email})

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
    insert_notification(%{
      reason: :periodic_reminder_producers,
      email: email = Ecto.UUID.generate() <> "@example.fr",
      role: :producer
    })

    assert [%DB.Notification{reason: :periodic_reminder_producers, email: ^email, role: :producer}] =
             DB.Notification |> DB.Repo.all()
  end

  test "recent_reasons" do
    dataset = insert(:dataset, is_active: true, datagouv_id: Ecto.UUID.generate())
    yesterday = DateTime.add(DateTime.utc_now(), -1, :day)
    email = Ecto.UUID.generate() <> "@example.com"
    other_email = Ecto.UUID.generate() <> "@example.com"
    reuser_email = Ecto.UUID.generate() <> "@example.com"

    # Should be ignored, this is an hidden reason
    insert_notification(%{dataset: dataset, role: :producer, reason: :dataset_now_on_nap, email: email})

    ns1 =
      insert_notification(%{
        dataset: dataset,
        role: :producer,
        reason: :dataset_with_error,
        email: email,
        payload: %{"job_id" => 1},
        inserted_at: %{yesterday | hour: 10, minute: 22}
      })

    insert_notification(%{
      dataset: dataset,
      role: :producer,
      reason: :dataset_with_error,
      email: other_email,
      payload: %{"job_id" => 1},
      inserted_at: %{yesterday | hour: 10, minute: 23}
    })

    ns2 =
      insert_notification(%{
        dataset: dataset,
        role: :producer,
        reason: :expiration,
        email: email,
        payload: %{"job_id" => 2},
        inserted_at: %{yesterday | hour: 12, minute: 44}
      })

    # Should be ignored: it's not for an enabled reason
    insert_notification(%{
      role: :producer,
      reason: :promote_producer_space,
      email: email,
      payload: %{"job_id" => 3},
      inserted_at: %{yesterday | hour: 15, minute: 32}
    })

    # Should be ignored: it's for a reuser
    insert_notification(%{
      dataset: dataset,
      role: :reuser,
      reason: :expiration,
      email: reuser_email,
      payload: %{"job_id" => 4},
      inserted_at: %{yesterday | hour: 11, minute: 42}
    })

    assert [
             %{reason: :expiration, timestamp: ns2.inserted_at, payload: %{"job_id" => 2}},
             %{reason: :dataset_with_error, timestamp: ns1.inserted_at, payload: %{"job_id" => 1}}
           ] == DB.Notification.recent_reasons(dataset, 7)
  end
end
