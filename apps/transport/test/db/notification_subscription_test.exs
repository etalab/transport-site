defmodule DB.NotificationSubscriptionTest do
  use ExUnit.Case, async: true
  import DB.Factory
  alias DB.NotificationSubscription

  doctest NotificationSubscription, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "changeset" do
    contact = insert_contact()
    dataset = insert(:dataset)
    changeset = fn args -> NotificationSubscription.changeset(%NotificationSubscription{}, args) end

    # valid cases
    assert %Ecto.Changeset{valid?: true} =
             changeset.(%{
               source: :admin,
               reason: :datasets_switching_climate_resilience_bill,
               contact_id: contact.id
             })

    assert %Ecto.Changeset{valid?: true} =
             changeset.(%{
               source: :admin,
               reason: :expiration,
               contact_id: contact.id,
               dataset_id: dataset.id
             })

    # `dataset_id` can't be blank and should exist if the `reason` is related to a dataset
    assert %Ecto.Changeset{valid?: false, errors: [dataset_id: {"can't be blank", [validation: :required]}]} =
             changeset.(%{
               source: :admin,
               reason: :expiration,
               contact_id: contact.id,
               dataset_id: nil
             })

    assert {:error, %Ecto.Changeset{valid?: false, errors: [dataset: {"does not exist", _}]}} =
             %{
               source: :admin,
               reason: :expiration,
               contact_id: contact.id,
               dataset_id: -1
             }
             |> changeset.()
             |> DB.Repo.insert()

    # `contact_id` can never be blank and should exist
    assert %Ecto.Changeset{valid?: false, errors: [contact_id: {"can't be blank", [validation: :required]}]} =
             changeset.(%{
               source: :admin,
               reason: :datasets_switching_climate_resilience_bill,
               contact_id: nil
             })

    assert {:error, %Ecto.Changeset{valid?: false, errors: [contact: {"does not exist", _}]}} =
             %{
               source: :admin,
               reason: :datasets_switching_climate_resilience_bill,
               contact_id: -1
             }
             |> changeset.()
             |> DB.Repo.insert()

    # `source` is an enum
    assert %Ecto.Changeset{valid?: false, errors: [source: {"is invalid", _}]} =
             changeset.(%{
               source: :foo,
               reason: :datasets_switching_climate_resilience_bill,
               contact_id: contact.id
             })
  end
end
