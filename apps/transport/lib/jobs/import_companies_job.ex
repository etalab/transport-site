defmodule Transport.Jobs.ImportCompaniesJob do
  @moduledoc """
  Imports or updates `DB.Company` records from the "Recherche d'entreprises API"
  for every distinct SIREN found in `DB.Dataset.legal_owner_company_siren`.

  The API has a rate limit of 7 requests per second.
  The orchestrator schedules individual worker jobs spread over time to stay within
  this limit: at most 7 jobs are scheduled per second using `schedule_in: div(index, 7)`.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query
  require Logger

  @rate_limit 7

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) when is_nil(args) or args == %{} do
    sirens()
    |> Enum.with_index()
    |> Enum.map(fn {siren, index} ->
      new(%{siren: siren}, schedule_in: div(index, @rate_limit))
    end)
    |> Oban.insert_all()

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"siren" => siren}}) do
    case Transport.Companies.by_siren(siren) do
      {:ok, result} ->
        upsert!(siren, result)

      {:error, reason} ->
        Logger.warning("#{inspect(__MODULE__)} could not fetch SIREN #{siren}: #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Returns distinct valid SIRENs from datasets.
  """
  def sirens do
    DB.Dataset.base_query()
    |> where([dataset: d], not is_nil(d.legal_owner_company_siren))
    |> select([dataset: d], d.legal_owner_company_siren)
    |> distinct(true)
    |> DB.Repo.all()
    |> Enum.filter(&Transport.Companies.is_valid_siren?/1)
  end

  defp parse_date(nil), do: nil
  defp parse_date(value), do: datetime_to_date(value)

  defp datetime_to_date(dt_string) when is_binary(dt_string) do
    {:ok, dt, 0} = "#{String.trim_trailing(dt_string, "Z")}Z" |> DateTime.from_iso8601()
    DateTime.to_date(dt)
  end

  defp parse_float(nil), do: nil
  defp parse_float(value), do: String.to_float(value)

  defp upsert!(siren, result) do
    attrs = %{
      siren: siren,
      nom_complet: result["nom_complet"],
      nom_raison_sociale: result["nom_raison_sociale"],
      sigle: result["sigle"],
      date_mise_a_jour_rne: parse_date(result["date_mise_a_jour_rne"]),
      siege_adresse: get_in(result, ["siege", "adresse"]),
      siege_latitude: parse_float(get_in(result, ["siege", "latitude"])),
      siege_longitude: parse_float(get_in(result, ["siege", "longitude"])),
      collectivite_territoriale: get_in(result, ["complements", "collectivite_territoriale"]),
      est_service_public: get_in(result, ["complements", "est_service_public"])
    }

    (DB.Repo.get(DB.Company, siren) || %DB.Company{})
    |> DB.Company.changeset(attrs)
    |> DB.Repo.insert_or_update!()
  end
end
