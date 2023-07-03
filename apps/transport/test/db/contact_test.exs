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
      phone_number: "06 82 22 88 03",
      secondary_phone_number: "+33 1 99 00 17 45"
    }
    |> DB.Contact.insert!()

    assert %DB.Contact{
             email: ^email,
             first_name: "John",
             job_title: "Chef SIG",
             last_name: "Doe",
             organization: "Big Corp Inc",
             phone_number: "+33682228803",
             secondary_phone_number: "+33199001745"
           } = DB.Repo.one!(DB.Contact)

    # Can search using `email_hash`
    assert 1 == DB.Contact |> where([n], n.email_hash == ^email) |> DB.Repo.all() |> Enum.count()

    # Cannot get rows by using the email/phone_number values, because values are encrypted
    assert DB.Contact |> where([n], n.email == ^email) |> DB.Repo.all() |> Enum.empty?()
    assert DB.Contact |> where([n], n.phone_number == ^"+33682228803") |> DB.Repo.all() |> Enum.empty?()
    assert DB.Contact |> where([n], n.secondary_phone_number == ^"+33199001745") |> DB.Repo.all() |> Enum.empty?()

    # Can save a contact with a `title`
    %{sample_contact_args() | first_name: nil, last_name: nil, mailing_list_title: "title"}
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

  test "validates that you can fill first_name/last_name OR mailing_list_title" do
    assert %Ecto.Changeset{
             valid?: false,
             errors: [first_name: {"You need to fill either first_name and last_name OR mailing_list_title", []}]
           } =
             DB.Contact.changeset(%DB.Contact{}, %{
               sample_contact_args()
               | first_name: "A",
                 last_name: "B",
                 mailing_list_title: "C"
             })

    assert %Ecto.Changeset{
             valid?: false,
             errors: [first_name: {"You need to fill either first_name and last_name OR mailing_list_title", []}]
           } =
             DB.Contact.changeset(%DB.Contact{}, %{
               sample_contact_args()
               | first_name: "A",
                 last_name: nil,
                 mailing_list_title: "C"
             })

    assert %Ecto.Changeset{
             valid?: false,
             errors: [first_name: {"You need to fill either first_name and last_name OR mailing_list_title", []}]
           } =
             DB.Contact.changeset(%DB.Contact{}, %{
               sample_contact_args()
               | first_name: nil,
                 last_name: "B",
                 mailing_list_title: "C"
             })

    assert %Ecto.Changeset{
             valid?: false,
             errors: [first_name: {"You need to fill first_name and last_name OR mailing_list_title", []}]
           } =
             DB.Contact.changeset(%DB.Contact{}, %{
               sample_contact_args()
               | first_name: nil,
                 last_name: nil,
                 mailing_list_title: nil
             })

    assert %Ecto.Changeset{valid?: true} =
             DB.Contact.changeset(%DB.Contact{}, %{
               sample_contact_args()
               | first_name: "A",
                 last_name: "B",
                 mailing_list_title: nil
             })

    assert %Ecto.Changeset{valid?: true} =
             DB.Contact.changeset(%DB.Contact{}, %{
               sample_contact_args()
               | first_name: nil,
                 last_name: nil,
                 mailing_list_title: "C"
             })
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
    DB.Contact.insert!(%{sample_contact_args() | first_name: "Marina", last_name: "Loiseau", organization: "CNRS"})

    DB.Contact.insert!(%{
      sample_contact_args()
      | first_name: nil,
        last_name: nil,
        mailing_list_title: "Service SIG",
        organization: "Geo Inc"
    })

    assert [%DB.Contact{last_name: "Doe"}] = search_fn.(%{"q" => "DOE"})
    assert [%DB.Contact{last_name: "Doe"}] = search_fn.(%{"q" => "doe"})
    assert [%DB.Contact{last_name: "Bar"}] = search_fn.(%{"q" => "bar"})
    assert [%DB.Contact{organization: "Foo Bar"}] = search_fn.(%{"q" => "Foo Bar"})
    assert [%DB.Contact{mailing_list_title: "Service SIG"}] = search_fn.(%{"q" => "SIG"})
    assert [%DB.Contact{first_name: "Marina"}] = search_fn.(%{"q" => "marina"})
  end

  test "organisations" do
    sample_contact_args()
    |> Map.merge(%{
      organizations: [
        %{
          "acronym" => nil,
          "badges" => [],
          "id" => Ecto.UUID.generate(),
          "logo" => "https://static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-original.png",
          "logo_thumbnail" => "https://static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-100.png",
          "name" => "PAN",
          "slug" => "equipe-transport-data-gouv-fr"
        },
        %{
          "acronym" => nil,
          "badges" => [],
          "id" => Ecto.UUID.generate(),
          "logo" => "https://static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-original.png",
          "logo_thumbnail" => "https://static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-100.png",
          "name" => "Big Corp",
          "slug" => "foo"
        }
      ]
    })
    |> DB.Contact.insert!()

    contact = DB.Contact |> DB.Repo.one!() |> DB.Repo.preload([:organizations])

    assert 2 == contact.organizations |> Enum.count()

    # Updating organizations by keeping just one
    contact
    |> DB.Contact.changeset(%{organizations: [contact.organizations |> hd() |> Map.from_struct()]})
    |> DB.Repo.update!()

    # The contact's organizations have been updated and we kept 2 organizations
    assert 1 ==
             contact
             |> DB.Repo.reload!()
             |> DB.Repo.preload([:organizations])
             |> Map.fetch!(:organizations)
             |> Enum.count()

    assert 2 == DB.Organization |> DB.Repo.all() |> Enum.count()
  end

  defp sample_contact_args do
    %{
      first_name: "John",
      last_name: "Doe",
      mailing_list_title: nil,
      email: "john#{Ecto.UUID.generate()}@example.fr",
      job_title: "Boss",
      organization: "Big Corp Inc",
      phone_number: "06 82 22 88 03"
    }
  end
end
