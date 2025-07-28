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

  test "search" do
    foo = insert(:reuse, title: "Foo", created_at: DateTime.utc_now())
    bar = insert(:reuse, owner: "Bar", created_at: DateTime.utc_now())
    hello = insert(:reuse, organization: "hello", created_at: DateTime.utc_now())

    search = fn value -> DB.Reuse.search(%{"q" => value}) |> DB.Repo.all() end

    assert [foo] == search.("foo")
    assert [bar] == search.("bar")
    assert [hello] == search.("héllo")
    # order by `created_at` desc
    assert [hello, bar, foo] == search.("")
  end
end
