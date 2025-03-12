defmodule Transport.Test.Transport.Jobs.ImportReusesJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox
  use Oban.Testing, repo: DB.Repo

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  @csv_url "https://www.data.gouv.fr/fr/datasets/r/970aafa0-3778-4d8b-b9d1-de937525e379"
  @dataset_datagouv_id Ecto.UUID.generate()

  test "perform" do
    %DB.Dataset{id: dataset_id} = insert(:dataset, datagouv_id: @dataset_datagouv_id)

    # An existing reuse will be deleted when importing all reuses
    DB.Reuse.changeset(%DB.Reuse{}, sample_reuse(Ecto.UUID.generate()))
    |> DB.Repo.insert!()

    assert 1 == DB.Repo.all(DB.Reuse) |> Enum.count()

    datagouv_id_1 = Ecto.UUID.generate()
    datagouv_id_2 = Ecto.UUID.generate()

    setup_csv_response([datagouv_id_1, datagouv_id_2])

    assert :ok == perform_job(Transport.Jobs.ImportReusesJob, %{})

    # We now have 2 reuses and they are associated with a dataset
    # The orphan reuse (not referencing an existing dataset) has been deleted.
    reuses = DB.Repo.all(DB.Reuse)
    assert MapSet.new([datagouv_id_1, datagouv_id_2]) == reuses |> Enum.map(& &1.datagouv_id) |> MapSet.new()
    assert %DB.Reuse{datasets: [%DB.Dataset{id: ^dataset_id}]} = reuses |> hd() |> DB.Repo.preload(:datasets)
  end

  defp sample_reuse(datagouv_id, datasets \\ [@dataset_datagouv_id]) do
    ~s|{"title": "Carte nationale des plateaux techniques spécialisés (PTS) pour « évaluer l’aptitude médicale à la conduite » ","slug": "carte-nationale-des-plateaux-techniques-specialises-pts-pour-evaluer-laptitude-medicale-a-la-conduite","url": "http://www.data.gouv.fr/fr/reuses/carte-nationale-des-plateaux-techniques-specialises-pts-pour-evaluer-laptitude-medicale-a-la-conduite/","type": "visualization","description": "Ceci est une description","remote_url": "https://www.securite-routiere.gouv.fr/permis-et-situation-de-handicap/carte-des-plateaux-techniques-de-sante","organization": null,"organization_id": null,"owner": "ilyes-zeroual","owner_id": "67c0216ab1f98413870cc70c","image": "https://static.data.gouv.fr/images/69/f0053e284741c9b6d2a73cc490edb2-500.png","featured": "False","created_at": "2025-02-27T09:18:54.658000","last_modified": "2025-02-27T09:49:33.676000","archived": "False","topic": "transport_and_mobility","tags": "foo,bar","metric.discussions": "0","metric.datasets": "2","metric.followers": "0","metric.views": "234"}|
    |> Jason.decode!()
    |> Map.put("id", datagouv_id)
    |> Map.put("datasets", Enum.join(datasets, ","))
  end

  defp setup_csv_response(datagouv_ids) do
    url = @csv_url
    orphan_reuse = sample_reuse(Ecto.UUID.generate(), [Ecto.UUID.generate()])

    body =
      (Enum.map(datagouv_ids, &sample_reuse/1) ++ [orphan_reuse])
      |> CSV.encode(headers: true, separator: ?;)
      |> Enum.join("")

    expect(Transport.Req.Mock, :get!, fn ^url, [decode_body: false] ->
      %Req.Response{status: 200, body: body}
    end)
  end
end
