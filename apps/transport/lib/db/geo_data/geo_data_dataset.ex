defmodule DB.GeoDataDataset do
  @moduledoc """
  A module to hold configuration of the datasets used in geodata queries and access them easily.
  """

  import Ecto.Query

  @datagouv_organization_id "646b7187b50b2a93b1ae3d45"
  # https://www.data.gouv.fr/fr/datasets/fichier-consolide-des-bornes-de-recharge-pour-vehicules-electriques/#/resources/eb76d20a-8501-400e-b336-d85724de5435
  @irve_resource_datagouv_id "eb76d20a-8501-400e-b336-d85724de5435"

  def irve_dataset do
    DB.Dataset.base_query()
    |> preload(:resources)
    |> where([d], d.type == "charging-stations" and d.organization_id == @datagouv_organization_id)
    |> DB.Repo.one()
  end

  def irve_resource do
    [resource] =
      irve_dataset()
      |> DB.Dataset.official_resources()
      |> Enum.filter(&match?(%DB.Resource{datagouv_id: @irve_resource_datagouv_id, format: "csv"}, &1))

    resource
  end
end
