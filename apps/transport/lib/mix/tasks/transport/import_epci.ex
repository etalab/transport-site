defmodule Mix.Tasks.Transport.ImportEPCI do
  @moduledoc """
  Import the EPCI file to get the relation between the cities and the EPCI
  """

  use Mix.Task
  alias Ecto.Changeset
  alias DB.{EPCI, Repo}

  @epci_file "https://unpkg.com/@etalab/decoupage-administratif@0.7.0/data/epci.json"

  def run(params) do
    if params[:no_start] do
      HTTPoison.start()
    else
      Mix.Task.run("app.start", [])
    end

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- HTTPoison.get(@epci_file),
         {:ok, json} <- Jason.decode(body) do
      json
      |> Enum.each(&insert_epci/1)
    end
  end

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

  defp insert_epci(%{"code" => code, "nom" => nom, "membres" => m}) do
    code
    |> get_or_create_epci()
    |> Changeset.change(%{
      code: code,
      nom: nom,
      communes_insee: get_insees(m)
    })
    |> IO.inspect()
    |> Repo.insert_or_update()
  end

  defp get_insees(members) do
    members
    |> Enum.map(fn m -> m["code"] end)
  end
end
