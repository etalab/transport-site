defmodule DB.ContactTest do
  use ExUnit.Case, async: true
  import DB.Factory
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
    search_fn = fn args -> args |> DB.Contact.search() |> order_by([contact: c], asc: c.id) |> DB.Repo.all() end
    assert search_fn.(%{}) == []

    DB.Contact.insert!(%{sample_contact_args() | last_name: "Doe", organization: "Big Corp Inc"})
    DB.Contact.insert!(%{sample_contact_args() | last_name: "Bar", organization: "Big Corp Inc"})
    DB.Contact.insert!(%{sample_contact_args() | last_name: "Baz", organization: "Foo Bar"})
    DB.Contact.insert!(%{sample_contact_args() | first_name: "Marina", last_name: "Loiseau", organization: "CNRS"})
    DB.Contact.insert!(%{sample_contact_args() | first_name: "Fabrice", last_name: "Mélo", organization: "CNRS"})

    DB.Contact.insert!(%{
      sample_contact_args()
      | first_name: nil,
        last_name: nil,
        mailing_list_title: "Service SIG",
        organization: "Geo Inc"
    })

    assert [%DB.Contact{last_name: "Doe"}] = search_fn.(%{"q" => "DOE"})
    assert [%DB.Contact{last_name: "Doe"}] = search_fn.(%{"q" => "doe"})
    assert [%DB.Contact{last_name: "Bar"}, %DB.Contact{organization: "Foo Bar"}] = search_fn.(%{"q" => "bar"})
    assert [%DB.Contact{organization: "Foo Bar"}] = search_fn.(%{"q" => "Foo Bar"})
    assert [%DB.Contact{mailing_list_title: "Service SIG"}] = search_fn.(%{"q" => "SIG"})
    assert [%DB.Contact{first_name: "Marina"}] = search_fn.(%{"q" => "marina"})
    assert [%DB.Contact{last_name: "Mélo"}] = search_fn.(%{"q" => "mel"})
    assert [%DB.Contact{last_name: "Mélo"}] = search_fn.(%{"q" => "mél"})
  end

  test "organisations" do
    pan_org = %{
      acronym: nil,
      badges: [],
      id: Ecto.UUID.generate(),
      logo: "https://static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-original.png",
      logo_thumbnail: "https://static.data.gouv.fr/avatars/85/53e0a3845e43eb87fb905032aaa389-100.png",
      name: "PAN",
      slug: "equipe-transport-data-gouv-fr"
    }

    insert(:organization, pan_org)

    sample_contact_args()
    |> Map.merge(%{
      organizations: [
        pan_org,
        %{
          "acronym" => nil,
          "badges" => [],
          "id" => Ecto.UUID.generate(),
          # Can save an org without logos
          "logo" => nil,
          "logo_thumbnail" => nil,
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

    # Not passing orgs should not delete orgs associated to the contact
    contact
    |> DB.Contact.changeset(%{first_name: "Robert"})
    |> DB.Repo.update!()

    assert 1 ==
             contact
             |> DB.Repo.reload!()
             |> DB.Repo.preload([:organizations])
             |> Map.fetch!(:organizations)
             |> Enum.count()
  end

  test "inactive contacts" do
    date1 = ~U[2022-04-01 13:00:00Z]
    date2 = ~U[2023-04-01 13:00:00Z]
    date3 = ~U[2024-04-01 13:00:00Z]
    date4 = ~U[2024-04-15 13:00:00Z]

    inactive = insert_contact(%{last_login_at: date1})
    active = insert_contact(%{last_login_at: date3})

    assert [inactive.id, active.id] == list_inactive_contact_ids(date4)
    assert [inactive.id] == list_inactive_contact_ids(date2)

    DB.Contact.delete_inactive_contacts(date2)

    assert [active.id] == list_inactive_contact_ids(date4)
    assert [] == list_inactive_contact_ids(date2)
  end

  test "admin_contact* methods" do
    admin_org = build(:organization, name: "Point d'Accès National transport.data.gouv.fr")
    %DB.Contact{id: admin_id} = admin_contact = insert_contact(%{organizations: [Map.from_struct(admin_org)]})
    insert_contact()

    assert [%DB.Contact{id: ^admin_id}] = DB.Contact.admin_contacts()
    assert [admin_id] == DB.Contact.admin_contact_ids()
    assert [admin_contact.datagouv_user_id] == DB.Contact.admin_datagouv_ids()
  end

  defp list_inactive_contact_ids(datetime) do
    DB.Contact.list_inactive_contacts(datetime)
    |> Enum.map(fn %DB.Contact{id: contact_id} -> contact_id end)
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
