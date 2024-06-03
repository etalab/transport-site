defmodule Transport.ConsolidatedDataset do
  @moduledoc """
  A module to hold configuration of the datasets used in geodata queries and access them easily.
  """

  import Ecto.Query

  # https://www.data.gouv.fr/fr/datasets/fichier-consolide-des-bornes-de-recharge-pour-vehicules-electriques/#/resources/eb76d20a-8501-400e-b336-d85724de5435

  def bnlc_dataset do
    transport_publisher_label = Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)

    DB.Dataset.base_query()
    |> preload(:resources)
    |> where([d], d.type == "carpooling-areas" and d.organization == ^transport_publisher_label)
    |> DB.Repo.one()
  end

  def bnlc_resource do
    %{resource_id: bnlc_resource_id} = Map.fetch!(Application.fetch_env!(:transport, :consolidation), :bnlc)

    [resource] =
      bnlc_dataset()
      |> DB.Dataset.official_resources()
      |> Enum.filter(fn %DB.Resource{datagouv_id: datagouv_id} -> datagouv_id == bnlc_resource_id end)

    resource
  end

  def irve_dataset do
    datagouv_publisher_label = Application.fetch_env!(:transport, :datagouvfr_publisher_label)

    DB.Dataset.base_query()
    |> preload(:resources)
    |> where([d], d.type == "charging-stations" and d.organization == ^datagouv_publisher_label)
    |> DB.Repo.one()
  end

  def irve_resource do
    %{resource_id: irve_resource_id} = Map.fetch!(Application.fetch_env!(:transport, :consolidation), :irve)

    [resource] =
      irve_dataset()
      |> DB.Dataset.official_resources()
      |> Enum.filter(&match?(%DB.Resource{datagouv_id: ^irve_resource_id, format: "csv"}, &1))

    resource
  end

  def parkings_relais_dataset do
    transport_publisher_label = Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)

    DB.Dataset.base_query()
    |> preload(:resources)
    |> where(
      [d],
      d.type == "private-parking" and d.organization == ^transport_publisher_label and
        d.custom_title == "Base nationale des parcs relais"
    )
    |> DB.Repo.one()
  end

  def parkings_relais_resource do
    [resource] = parkings_relais_dataset() |> DB.Dataset.official_resources() |> Enum.filter(&(&1.format == "csv"))

    resource
  end

  def zfe_dataset do
    transport_publisher_label = Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)

    DB.Dataset.base_query()
    |> preload(:resources)
    |> where([d], d.type == "low-emission-zones" and d.organization == ^transport_publisher_label)
    |> DB.Repo.one()
  end

  def zfe_resource do
    [resource] = zfe_dataset() |> DB.Dataset.official_resources() |> Enum.filter(&(&1.title == "aires.geojson"))

    resource
  end
end
