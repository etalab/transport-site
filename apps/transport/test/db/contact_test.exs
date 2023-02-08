defmodule DB.ContactTest do
  use ExUnit.Case, async: true
  import Ecto.Query

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "can save objects in the database with relevant casts" do
    %{
      first_name: "John ",
      last_name: " Doe",
      email: email = "john@example.fr",
      job_title: "Boss",
      organization: "Big Corp Inc",
      phone_number: "06 92 22 88 03"
    }
    |> DB.Contact.insert!()

    assert %DB.Contact{
             email: ^email,
             first_name: "John",
             job_title: "Boss",
             last_name: "Doe",
             organization: "Big Corp Inc",
             phone_number: "+33692228803"
           } = DB.Repo.one!(DB.Contact)

    # Can search using `email_hash`
    assert 1 == DB.Contact |> where([n], n.email_hash == ^email) |> DB.Repo.all() |> Enum.count()

    # Cannot get rows by using the email/phone_number values, because values are encrypted
    assert DB.Contact |> where([n], n.email == ^email) |> DB.Repo.all() |> Enum.empty?()
    assert DB.Contact |> where([n], n.email == ^"+33692228803") |> DB.Repo.all() |> Enum.empty?()
  end

  test "validates and formats phone numbers" do
    base_args = %{
      first_name: "John",
      last_name: "Doe",
      email: "john@example.fr",
      job_title: "Boss",
      organization: "Big Corp Inc",
      phone_number: nil
    }

    assert %Ecto.Changeset{valid?: false, errors: [phone_number: {"Phone number is not a possible number", []}]} =
             DB.Contact.changeset(%DB.Contact{}, %{base_args | phone_number: "999"})

    assert %Ecto.Changeset{valid?: false, errors: [phone_number: {"Phone number is not a valid number", []}]} =
             DB.Contact.changeset(%DB.Contact{}, %{base_args | phone_number: "06 92 22 88 0"})

    assert %Ecto.Changeset{valid?: true, changes: %{phone_number: "+33699999999"}} =
             DB.Contact.changeset(%DB.Contact{}, %{base_args | phone_number: "+33 6 99 99 99 99"})

    assert %Ecto.Changeset{valid?: true, changes: %{phone_number: "+33699999999"}} =
             DB.Contact.changeset(%DB.Contact{}, %{base_args | phone_number: "+33.6.99.99.99.99"})

    assert %Ecto.Changeset{valid?: true, changes: %{phone_number: "+33699999999"}} =
             DB.Contact.changeset(%DB.Contact{}, %{base_args | phone_number: "06.99.99.99.99"})

    assert %Ecto.Changeset{valid?: true, changes: %{phone_number: "+14383898482"}} =
             DB.Contact.changeset(%DB.Contact{}, %{base_args | phone_number: "+1 (438) 389 8482"})
  end
end
