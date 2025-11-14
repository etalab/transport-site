defmodule DB.DatasetFollowerTest do
  # The trigger refresh_dataset_geographic_view_trigger makes this test
  # unreliable in a concurrent setup.
  use ExUnit.Case, async: false
  import DB.Factory
  alias DB.DatasetFollower

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "changeset" do
    contact = insert_contact()
    dataset = insert(:dataset)

    # Valid case
    assert %Ecto.Changeset{valid?: true} =
             changeset(%{dataset_id: dataset.id, contact_id: contact.id, source: :datagouv})

    # Errors
    assert {:error, %Ecto.Changeset{errors: [contact: {"does not exist", _}]}} =
             %{dataset_id: dataset.id, contact_id: -1, source: :datagouv} |> changeset() |> DB.Repo.insert()

    assert {:error, %Ecto.Changeset{errors: [dataset: {"does not exist", _}]}} =
             %{dataset_id: -1, contact_id: contact.id, source: :datagouv} |> changeset() |> DB.Repo.insert()

    assert {:error, %Ecto.Changeset{errors: [source: {"is invalid", _}]}} =
             %{dataset_id: dataset.id, contact_id: contact.id, source: :foo} |> changeset() |> DB.Repo.insert()

    # Unique constraint is enforced
    %{dataset_id: dataset.id, contact_id: contact.id, source: :datagouv} |> changeset() |> DB.Repo.insert!()

    assert {:error, %Ecto.Changeset{errors: [dataset_id: {"has already been taken", _}]}} =
             %{dataset_id: dataset.id, contact_id: contact.id, source: :datagouv} |> changeset() |> DB.Repo.insert()
  end

  test "foreign relations" do
    %DB.Contact{id: contact_id} = contact = insert_contact()
    %DB.Dataset{id: dataset_id} = dataset = insert(:dataset)

    assert [] = dataset |> DB.Repo.preload(:followers) |> Map.fetch!(:followers)
    assert [] = contact |> DB.Repo.preload(:followed_datasets) |> Map.fetch!(:followed_datasets)

    %{dataset_id: dataset_id, contact_id: contact_id, source: :datagouv} |> changeset() |> DB.Repo.insert!()

    # Updating the dataset does not affect followers
    {:ok, %Ecto.Changeset{} = changeset} =
      DB.Dataset.changeset(%{"datagouv_id" => dataset.datagouv_id, "custom_title" => "Foo"})

    DB.Repo.update!(changeset)

    assert [%DB.Contact{id: ^contact_id}] = dataset |> DB.Repo.preload(:followers) |> Map.fetch!(:followers)

    assert [%DB.Dataset{id: ^dataset_id}] =
             contact |> DB.Repo.preload(:followed_datasets) |> Map.fetch!(:followed_datasets)
  end

  test "follows_dataset" do
    %DB.Contact{id: contact_id} = contact = insert_contact()
    %DB.Dataset{id: dataset_id} = dataset = insert(:dataset)

    refute DB.DatasetFollower.follows_dataset?(nil, dataset)
    refute DB.DatasetFollower.follows_dataset?(contact, dataset)

    %{dataset_id: dataset_id, contact_id: contact_id, source: :datagouv} |> changeset() |> DB.Repo.insert!()

    assert DB.DatasetFollower.follows_dataset?(contact, dataset)
  end

  test "follow! and unfollow!" do
    %DB.Contact{} = contact = insert_contact()
    %DB.Dataset{} = dataset = insert(:dataset)

    refute DB.DatasetFollower.follows_dataset?(contact, dataset)

    DB.DatasetFollower.follow!(contact, dataset, source: :follow_button)

    assert DB.DatasetFollower.follows_dataset?(contact, dataset)

    DB.DatasetFollower.unfollow!(contact, dataset)

    refute DB.DatasetFollower.follows_dataset?(contact, dataset)
  end

  defp changeset(args), do: DatasetFollower.changeset(%DatasetFollower{}, args)
end
