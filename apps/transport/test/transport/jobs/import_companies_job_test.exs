defmodule Transport.Test.Transport.Jobs.ImportCompaniesJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Ecto.Query
  import Mox
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.ImportCompaniesJob

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  # Société Air France
  @siren "420495178"
  # Danone
  @other_siren "552032534"

  describe "orchestrator" do
    test "enqueues one job per distinct valid SIREN" do
      insert(:dataset, legal_owner_company_siren: @siren)
      insert(:dataset, legal_owner_company_siren: @siren)
      insert(:dataset, legal_owner_company_siren: @other_siren)
      # Invalid SIREN: should be ignored
      insert(:dataset, legal_owner_company_siren: "123456789")
      # nil: should be ignored
      insert(:dataset, legal_owner_company_siren: nil)

      assert :ok == perform_job(ImportCompaniesJob, %{})

      enqueued = all_enqueued(worker: ImportCompaniesJob)
      assert length(enqueued) == 2
      assert Enum.map(enqueued, & &1.args["siren"]) |> MapSet.new() == MapSet.new([@siren, @other_siren])
    end

    test "schedules jobs to respect rate limit of 7 requests per second" do
      # 7 additional valid SIRENs + @siren = 8 total
      # With rate limit 7: indices 0-6 at second 0, index 7 at second 1 → 2 distinct scheduled times
      valid_sirens = [
        "552032534",
        "320878499",
        "552144503",
        "775670417",
        "334024155",
        "253800825",
        "217500016"
      ]

      for siren <- [@siren | valid_sirens] do
        # insert duplicates to verify deduplication
        insert(:dataset, legal_owner_company_siren: siren)
        insert(:dataset, legal_owner_company_siren: siren)
      end

      assert :ok == perform_job(ImportCompaniesJob, %{})

      enqueued = all_enqueued(worker: ImportCompaniesJob)
      assert length(enqueued) == 8

      # Truncate to the second to compare scheduling buckets
      scheduled_buckets =
        enqueued
        |> Enum.map(& &1.scheduled_at)
        |> Enum.map(&DateTime.truncate(&1, :second))
        |> Enum.uniq()

      assert length(scheduled_buckets) == 2
    end
  end

  describe "worker" do
    test "creates a company when it does not exist" do
      result = api_result(@siren)

      setup_http_response(
        @siren,
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"results" => [result]})}}
      )

      assert :ok == perform_job(ImportCompaniesJob, %{siren: @siren})

      company = DB.Repo.one!(from(c in DB.Company, where: c.siren == ^@siren))
      assert company.nom_complet == "AIR FRANCE"
      assert company.nom_raison_sociale == "AIR FRANCE"
      assert company.sigle == "AF"
      assert company.date_mise_a_jour_rne == ~D[2023-01-15]
      assert company.siege_adresse == "45 RUE DE PARIS 95747 ROISSY-EN-FRANCE"
      assert company.siege_latitude == 49.003869
      assert company.siege_longitude == 2.563512
      assert company.collectivite_territoriale == nil
      assert company.est_service_public == true
    end

    test "updates an existing company" do
      DB.Repo.insert!(%DB.Company{siren: @siren, nom_complet: "OLD NAME"})

      result = api_result(@siren)

      setup_http_response(
        @siren,
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"results" => [result]})}}
      )

      assert :ok == perform_job(ImportCompaniesJob, %{siren: @siren})

      assert DB.Repo.one!(from(c in DB.Company, where: c.siren == ^@siren)).nom_complet == "AIR FRANCE"
      assert DB.Repo.aggregate(DB.Company, :count) == 1
    end

    test "collectivite_territoriale stores the map from the API response" do
      ct = %{"code" => "75", "code_insee" => "75056"}

      result =
        @siren
        |> api_result()
        |> put_in(["complements", "collectivite_territoriale"], ct)

      setup_http_response(
        @siren,
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"results" => [result]})}}
      )

      assert :ok == perform_job(ImportCompaniesJob, %{siren: @siren})

      assert DB.Repo.one!(from(c in DB.Company, where: c.siren == ^@siren)).collectivite_territoriale == ct
    end

    test "logs a warning and does not crash when the API returns an error" do
      setup_http_response(@siren, {:ok, %HTTPoison.Response{status_code: 500}})

      {result, log} = ExUnit.CaptureLog.with_log(fn -> perform_job(ImportCompaniesJob, %{siren: @siren}) end)

      assert result == :ok
      assert log =~ "could not fetch SIREN #{@siren}"
      assert log =~ "invalid_http_response"
      assert DB.Repo.aggregate(DB.Company, :count) == 0
    end

    test "logs a warning and does not crash when SIREN is not found in API results" do
      setup_http_response(@siren, {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"results" => []})}})

      {result, log} = ExUnit.CaptureLog.with_log(fn -> perform_job(ImportCompaniesJob, %{siren: @siren}) end)

      assert result == :ok
      assert log =~ "could not fetch SIREN #{@siren}"
      assert log =~ "result_not_found"
      assert DB.Repo.aggregate(DB.Company, :count) == 0
    end
  end

  describe "sirens/0" do
    test "returns distinct valid SIRENs from datasets" do
      insert(:dataset, legal_owner_company_siren: @siren)
      insert(:dataset, legal_owner_company_siren: @siren)
      insert(:dataset, legal_owner_company_siren: @other_siren)
      insert(:dataset, legal_owner_company_siren: nil)
      insert(:dataset, legal_owner_company_siren: "123456789")

      assert MapSet.new(ImportCompaniesJob.sirens()) == MapSet.new([@siren, @other_siren])
    end
  end

  defp api_result(siren) do
    %{
      "siren" => siren,
      "nom_complet" => "AIR FRANCE",
      "nom_raison_sociale" => "AIR FRANCE",
      "sigle" => "AF",
      "date_mise_a_jour_rne" => "2023-01-15",
      "siege" => %{
        "adresse" => "45 RUE DE PARIS 95747 ROISSY-EN-FRANCE",
        "latitude" => "49.003869",
        "longitude" => "2.563512"
      },
      "complements" => %{
        "collectivite_territoriale" => nil,
        "est_service_public" => true
      }
    }
  end

  defp setup_http_response(siren, response) do
    uri = %URI{
      scheme: "https",
      host: "recherche-entreprises.api.gouv.fr",
      port: 443,
      path: "/search",
      query: "mtm_campaign=transport-data-gouv-fr&q=#{siren}"
    }

    Transport.HTTPoison.Mock |> expect(:get, fn ^uri -> response end)
  end
end
