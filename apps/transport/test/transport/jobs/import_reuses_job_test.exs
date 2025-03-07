defmodule Transport.Test.Transport.Jobs.ImportReusesJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox
  use Oban.Testing, repo: DB.Repo

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  @start_url "https://tabular-api.data.gouv.fr/api/resources/970aafa0-3778-4d8b-b9d1-de937525e379/data/?page=1&page_size=50&topic__exact=transport_and_mobility"
  @dataset_datagouv_id Ecto.UUID.generate()

  test "perform" do
    %DB.Dataset{id: dataset_id} = insert(:dataset, datagouv_id: @dataset_datagouv_id)

    # An existing reuse will be deleted when importing all reuses
    DB.Reuse.changeset(%DB.Reuse{}, sample_reuse(Ecto.UUID.generate()))
    |> DB.Repo.insert!()

    assert 1 == DB.Repo.all(DB.Reuse) |> Enum.count()

    datagouv_id_1 = Ecto.UUID.generate()
    datagouv_id_2 = Ecto.UUID.generate()
    next_page = "https://example.com/next"

    setup_http_response(@start_url, [sample_reuse(datagouv_id_1)], next_page)
    setup_http_response(next_page, [sample_reuse(datagouv_id_2)], nil)

    assert :ok == perform_job(Transport.Jobs.ImportReusesJob, %{})

    # We now have 2 reuses and they are associated with a dataset
    reuses = DB.Repo.all(DB.Reuse)
    assert MapSet.new([datagouv_id_1, datagouv_id_2]) == reuses |> Enum.map(& &1.datagouv_id) |> MapSet.new()
    assert %DB.Reuse{datasets: [%DB.Dataset{id: ^dataset_id}]} = reuses |> hd() |> DB.Repo.preload(:datasets)
  end

  defp sample_reuse(datagouv_id) do
    ~s|{"id": "#{datagouv_id}","title": "Carte nationale des plateaux techniques spécialisés (PTS) pour « évaluer l’aptitude médicale à la conduite » ","slug": "carte-nationale-des-plateaux-techniques-specialises-pts-pour-evaluer-laptitude-medicale-a-la-conduite","url": "http://www.data.gouv.fr/fr/reuses/carte-nationale-des-plateaux-techniques-specialises-pts-pour-evaluer-laptitude-medicale-a-la-conduite/","type": "visualization","description": "Ceci est une description","remote_url": "https://www.securite-routiere.gouv.fr/permis-et-situation-de-handicap/carte-des-plateaux-techniques-de-sante","organization": null,"organization_id": null,"owner": "ilyes-zeroual","owner_id": "67c0216ab1f98413870cc70c","image": "https://static.data.gouv.fr/images/69/f0053e284741c9b6d2a73cc490edb2-500.png","featured": false,"created_at": "2025-02-27T09:18:54.658000","last_modified": "2025-02-27T09:49:33.676000","archived": "False","topic": "transport_and_mobility","tags": "foo,bar","datasets": "54730e00c751df4f2ec2acbe,#{@dataset_datagouv_id}","metric.discussions": 0,"metric.datasets": 2,"metric.followers": 0,"metric.views": 234}|
    |> Jason.decode!()
  end

  defp setup_http_response(url, data, next_url) do
    expect(Transport.Req.Mock, :get, fn ^url, [] ->
      {:ok, %Req.Response{status: 200, body: %{"data" => data, "links" => %{"next" => next_url}}}}
    end)
  end
end
