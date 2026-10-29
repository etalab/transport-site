defmodule DB.ReuseTest do
  use ExUnit.Case, async: true
  import DB.Factory

  doctest DB.Reuse, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "changeset" do
    %DB.Dataset{id: dataset_id} = insert(:dataset, datagouv_id: datagouv_id = "53699569a3a729239d2046eb")

    # Payload from https://tabular-api.data.gouv.fr/api/resources/970aafa0-3778-4d8b-b9d1-de937525e379/data/?page=1&page_size=50&topic__exact=transport_and_mobility
    data =
      ~s|{"id": "67c02dfe7172569a69c367e6","title": "Carte nationale des plateaux techniques spécialisés (PTS) pour « évaluer l’aptitude médicale à la conduite » ","slug": "carte-nationale-des-plateaux-techniques-specialises-pts-pour-evaluer-laptitude-medicale-a-la-conduite","url": "http://www.data.gouv.fr/fr/reuses/carte-nationale-des-plateaux-techniques-specialises-pts-pour-evaluer-laptitude-medicale-a-la-conduite/","type": "visualization","description": "Ceci est une description","remote_url": "https://www.securite-routiere.gouv.fr/permis-et-situation-de-handicap/carte-des-plateaux-techniques-de-sante","organization": null,"organization_id": null,"owner": "ilyes-zeroual","owner_id": "67c0216ab1f98413870cc70c","image": "https://static.data.gouv.fr/images/69/f0053e284741c9b6d2a73cc490edb2-500.png","featured": "False","created_at": "2025-02-27T09:18:54.658000","last_modified": "2025-02-27T09:49:33.676000","archived": "False","topic": "transport_and_mobility","tags": "foo,bar","datasets": "54730e00c751df4f2ec2acbe,#{datagouv_id}","metric.discussions": "0","metric.datasets": "2","metric.followers": "0","metric.followers_by_months": "0","metric.views": "234"}|

    assert %Ecto.Changeset{
             valid?: true,
             changes: %{
               datagouv_id: "67c02dfe7172569a69c367e6",
               tags: ["foo", "bar"],
               metric_views: 234,
               archived: false,
               featured: false,
               created_at: ~U[2025-02-27 09:18:54.658000Z]
             }
           } = changeset = DB.Reuse.changeset(%DB.Reuse{}, Jason.decode!(data))

    DB.Repo.insert!(changeset)

    [reuse] = DB.Repo.all(DB.Reuse)
    assert [%DB.Dataset{id: ^dataset_id}] = reuse |> DB.Repo.preload(:datasets) |> Map.fetch!(:datasets)
  end

  test "by_dataset_datagouv_id returns reuses for a dataset" do
    d1 = insert(:dataset, datagouv_id: datagouv_id_1 = Ecto.UUID.generate())
    d2 = insert(:dataset, datagouv_id: _datagouv_id_2 = Ecto.UUID.generate())

    reuse1 = insert(:reuse, datasets: [d1], last_modified: ~U[2025-06-01 12:00:00Z])
    reuse2 = insert(:reuse, datasets: [d1], last_modified: ~U[2025-07-15 09:30:00Z])
    insert(:reuse, datasets: [d2], last_modified: ~U[2025-08-20 18:00:00Z])

    result = DB.Reuse.by_dataset_datagouv_id(datagouv_id_1)

    assert length(result) == 2
    ids = Enum.map(result, & &1.datagouv_id)
    assert reuse1.datagouv_id in ids
    assert reuse2.datagouv_id in ids

    # All expected fields are present
    [
      %{
        title: t,
        slug: s,
        remote_url: _ru,
        description: desc,
        image: _img,
        organization: org,
        owner: ow,
        last_modified: lm
      }
      | _
    ] = result

    assert is_binary(t) and is_binary(s) and is_binary(desc)
    assert is_struct(lm, DateTime)
    # Organization/owner are set by the factory
    assert is_binary(org) or is_nil(org)
    assert is_binary(ow) or is_map(ow) or is_nil(ow)
  end

  test "by_dataset_datagouv_id returns empty list for unknown dataset" do
    assert [] == DB.Reuse.by_dataset_datagouv_id(Ecto.UUID.generate())
  end

  test "search" do
    d1 = insert(:dataset, type: "public-transit")
    d2 = insert(:dataset, type: "private-parking")
    foo = insert(:reuse, title: "Foo", datasets: [d1], created_at: DateTime.utc_now())
    bar = insert(:reuse, owner: "Bar", datasets: [d1], created_at: DateTime.utc_now())
    hello = insert(:reuse, organization: "hello", datasets: [d2], created_at: DateTime.utc_now())

    assert [foo.id] == DB.Reuse.search(%{"q" => "foo"}) |> DB.Repo.all() |> Enum.map(& &1.id)
    assert [bar.id] == DB.Reuse.search(%{"q" => "bar"}) |> DB.Repo.all() |> Enum.map(& &1.id)
    assert [hello.id] == DB.Reuse.search(%{"q" => "héllo"}) |> DB.Repo.all() |> Enum.map(& &1.id)

    # order by `created_at` desc
    assert [hello.id, bar.id, foo.id] == DB.Reuse.search(%{}) |> DB.Repo.all() |> Enum.map(& &1.id)

    # filter by type
    assert [bar.id, foo.id] ==
             DB.Reuse.search(%{"type" => "public-transit"}) |> DB.Repo.all() |> Enum.map(& &1.id)
  end
end
