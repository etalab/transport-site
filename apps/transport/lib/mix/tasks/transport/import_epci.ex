defmodule Mix.Tasks.Transport.ImportEPCI do
  @moduledoc """
  Import the EPCI file to get the relation between the cities and the EPCI
  """

  use Mix.Task
  import Ecto.Query
  alias Ecto.Changeset
  alias DB.{EPCI, Repo}
  require Logger

  @epci_file "https://unpkg.com/@etalab/decoupage-administratif@2.0.0/data/epci.json"

  def run(params) do
    Logger.info("importing epci")

    if params[:no_start] do
      HTTPoison.start()
    else
      Mix.Task.run("app.start", [])
    end

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- HTTPoison.get(@epci_file),
         {:ok, json} <- Jason.decode(body) do
      json |> Enum.each(&insert_epci/1)

      # Remove EPCIs that have been removed
      epci_codes = Enum.map(json, & &1["code"])
      EPCI |> where([e], e.code not in ^epci_codes) |> Repo.delete_all()

      nb_epci = Repo.aggregate(EPCI, :count, :id)
      Logger.info("#{nb_epci} are now in database")
      :ok
    else
      e ->
        Logger.warn("impossible to fetch epci file, error #{inspect(e)}")
        :error
    end
  end

  @spec get_or_create_epci(binary()) :: EPCI.t()
  defp get_or_create_epci(code) do
    EPCI
    |> Repo.get_by(code: code)
    |> case do
      nil ->
        %EPCI{}

      epci ->
        epci
    end
  end

  @spec insert_epci(map()) :: any()
  defp insert_epci(%{"code" => code, "nom" => nom, "membres" => m}) do
    code
    |> get_or_create_epci()
    |> Changeset.change(%{
      code: code,
      nom: nom,
      communes_insee: get_insees(m)
    })
    |> Repo.insert_or_update()
  end

  @spec get_insees([map()]) :: [binary()]
  defp get_insees(members) do
    members
    |> Enum.map(fn m -> m["code"] end)
  end
end
