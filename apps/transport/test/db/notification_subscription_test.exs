defmodule DB.NotificationSubscriptionTest do
  use ExUnit.Case, async: true
  import DB.Factory
  alias DB.NotificationSubscription

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "changeset" do
    contact = DB.Contact.insert!(sample_contact_args())
    dataset = insert(:dataset)
    changeset = fn args -> NotificationSubscription.changeset(%NotificationSubscription{}, args) end

    # valid cases
    assert %Ecto.Changeset{valid?: true} =
             changeset.(%{
               source: :admin,
               reason: :dataset_now_licence_ouverte,
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
               reason: :dataset_now_licence_ouverte,
               contact_id: nil
             })

    assert {:error, %Ecto.Changeset{valid?: false, errors: [contact: {"does not exist", _}]}} =
             %{
               source: :admin,
               reason: :dataset_now_licence_ouverte,
               contact_id: -1
             }
             |> changeset.()
             |> DB.Repo.insert()

    # `source` is an enum
    assert %Ecto.Changeset{valid?: false, errors: [source: {"is invalid", _}]} =
             changeset.(%{
               source: :foo,
               reason: :dataset_now_licence_ouverte,
               contact_id: contact.id
             })
  end

  defp sample_contact_args do
    %{
      first_name: "John",
      last_name: "Doe",
      email: "john#{Ecto.UUID.generate()}@example.fr",
      job_title: "Boss",
      organization: "Big Corp Inc",
      phone_number: "06 92 22 88 03"
    }
  end
end
