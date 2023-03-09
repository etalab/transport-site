defmodule DB.ContactTest do
  use ExUnit.Case, async: true
  import Ecto.Query

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  doctest DB.Contact, import: true

  test "can save objects in the database with relevant casts" do
    %{
      first_name: "john ",
      last_name: " doe",
      email: email = "john@example.fr",
      job_title: "Chef SIG",
      organization: "Big Corp Inc",
      phone_number: "06 92 22 88 03"
    }
    |> DB.Contact.insert!()

    assert %DB.Contact{
             email: ^email,
             first_name: "John",
             job_title: "Chef SIG",
             last_name: "Doe",
             organization: "Big Corp Inc",
             phone_number: "+33692228803"
           } = DB.Repo.one!(DB.Contact)

    # Can search using `email_hash`
    assert 1 == DB.Contact |> where([n], n.email_hash == ^email) |> DB.Repo.all() |> Enum.count()

    # Cannot get rows by using the email/phone_number values, because values are encrypted
    assert DB.Contact |> where([n], n.email == ^email) |> DB.Repo.all() |> Enum.empty?()
    assert DB.Contact |> where([n], n.email == ^"+33692228803") |> DB.Repo.all() |> Enum.empty?()

    # Can save a contact with a `title`
    %{sample_contact_args() | first_name: nil, last_name: nil, title: "title"}
    |> DB.Contact.insert!()

    assert 2 == DB.Contact |> DB.Repo.aggregate(:count, :id)
  end

  test "validates and formats phone numbers" do
    assert %Ecto.Changeset{
             valid?: false,
             errors: [phone_number: {"The string supplied did not seem to be a phone number", []}]
           } = DB.Contact.changeset(%DB.Contact{}, %{sample_contact_args() | phone_number: "🤡"})

    assert %Ecto.Changeset{valid?: false, errors: [phone_number: {"Phone number is not a possible number", []}]} =
             DB.Contact.changeset(%DB.Contact{}, %{sample_contact_args() | phone_number: "999"})

    assert %Ecto.Changeset{valid?: false, errors: [phone_number: {"Phone number is not a valid number", []}]} =
             DB.Contact.changeset(%DB.Contact{}, %{sample_contact_args() | phone_number: "06 92 22 88 0"})

    assert %Ecto.Changeset{valid?: true, changes: %{phone_number: "+33699999999"}} =
             DB.Contact.changeset(%DB.Contact{}, %{sample_contact_args() | phone_number: "+33 6 99 99 99 99"})

    assert %Ecto.Changeset{valid?: true, changes: %{phone_number: "+33699999999"}} =
             DB.Contact.changeset(%DB.Contact{}, %{sample_contact_args() | phone_number: "+33.6.99.99.99.99"})

    assert %Ecto.Changeset{valid?: true, changes: %{phone_number: "+33699999999"}} =
             DB.Contact.changeset(%DB.Contact{}, %{sample_contact_args() | phone_number: "06.99.99.99.99"})

    assert %Ecto.Changeset{valid?: true, changes: %{phone_number: "+14383898482"}} =
             DB.Contact.changeset(%DB.Contact{}, %{sample_contact_args() | phone_number: "+1 (438) 389 8482"})
  end

  test "validates that you can fill first_name/last_name OR title" do
    assert %Ecto.Changeset{
             valid?: false,
             errors: [first_name: {"You need to fill either first_name and last_name OR title", []}]
           } =
             DB.Contact.changeset(%DB.Contact{}, %{sample_contact_args() | first_name: "A", last_name: "B", title: "C"})

    assert %Ecto.Changeset{
             valid?: false,
             errors: [first_name: {"You need to fill either first_name and last_name OR title", []}]
           } =
             DB.Contact.changeset(%DB.Contact{}, %{sample_contact_args() | first_name: "A", last_name: nil, title: "C"})

    assert %Ecto.Changeset{
             valid?: false,
             errors: [first_name: {"You need to fill either first_name and last_name OR title", []}]
           } =
             DB.Contact.changeset(%DB.Contact{}, %{sample_contact_args() | first_name: nil, last_name: "B", title: "C"})

    assert %Ecto.Changeset{
             valid?: false,
             errors: [first_name: {"You need to fill first_name and last_name OR title", []}]
           } =
             DB.Contact.changeset(%DB.Contact{}, %{sample_contact_args() | first_name: nil, last_name: nil, title: nil})

    assert %Ecto.Changeset{valid?: true} =
             DB.Contact.changeset(%DB.Contact{}, %{sample_contact_args() | first_name: "A", last_name: "B", title: nil})

    assert %Ecto.Changeset{valid?: true} =
             DB.Contact.changeset(%DB.Contact{}, %{sample_contact_args() | first_name: nil, last_name: nil, title: "C"})
  end

  test "cannot have duplicates based on email" do
    params = %{sample_contact_args() | email: "foo@example.fr"}

    DB.Contact.insert!(params)

    assert {:error,
            %Ecto.Changeset{action: :insert, errors: [email: {"has already been taken", _}], data: _, valid?: false}} =
             %DB.Contact{}
             |> DB.Contact.changeset(params)
             |> DB.Repo.insert_or_update()
  end

  test "email is lowercased" do
    assert %DB.Contact{email: "foo.bar@example.fr"} =
             DB.Contact.insert!(%{sample_contact_args() | email: "foo.BAR@example.fr"})
  end

  test "search" do
    search_fn = fn args -> args |> DB.Contact.search() |> DB.Repo.all() end
    assert search_fn.(%{}) == []

    DB.Contact.insert!(%{sample_contact_args() | last_name: "Doe", organization: "Big Corp Inc"})
    DB.Contact.insert!(%{sample_contact_args() | last_name: "Bar", organization: "Big Corp Inc"})
    DB.Contact.insert!(%{sample_contact_args() | last_name: "Baz", organization: "Foo Bar"})

    DB.Contact.insert!(%{
      sample_contact_args()
      | first_name: nil,
        last_name: nil,
        title: "Service SIG",
        organization: "Geo Inc"
    })

    assert [%DB.Contact{last_name: "Doe"}] = search_fn.(%{"q" => "DOE"})
    assert [%DB.Contact{last_name: "Doe"}] = search_fn.(%{"q" => "doe"})
    assert [%DB.Contact{last_name: "Bar"}] = search_fn.(%{"q" => "bar"})
    assert [%DB.Contact{organization: "Foo Bar"}] = search_fn.(%{"q" => "Foo Bar"})
    assert [%DB.Contact{title: "Service SIG"}] = search_fn.(%{"q" => "SIG"})
  end

  defp sample_contact_args do
    %{
      first_name: "John",
      last_name: "Doe",
      title: nil,
      email: "john#{Ecto.UUID.generate()}@example.fr",
      job_title: "Boss",
      organization: "Big Corp Inc",
      phone_number: "06 92 22 88 03"
    }
  end
end
