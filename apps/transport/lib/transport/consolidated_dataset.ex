defmodule Transport.ConsolidatedDataset do
  @moduledoc """
  A module to hold configuration of the datasets used in geodata queries and access them easily.
  """

  import Ecto.Query

  def bnlc_dataset do
    base_consolidated_dataset_query("carpooling-areas", :transport)
  end

  def irve_dataset do
    base_consolidated_dataset_query("charging-stations", :datagouvfr)
  end

  def parkings_relais_dataset do
    additional_fn = fn query ->
      query |> where([d], d.custom_title == "Base nationale des parcs relais")
    end

    base_consolidated_dataset_query("private-parking", :transport, additional_fn)
  end

  def zfe_dataset do
    base_consolidated_dataset_query("low-emission-zones", :transport)
  end

  def bnlc_resource do
    %{resource_id: bnlc_resource_id} = Map.fetch!(Application.fetch_env!(:transport, :consolidation), :bnlc)

    [resource] =
      bnlc_dataset()
      |> DB.Dataset.official_resources()
      |> Enum.filter(fn %DB.Resource{datagouv_id: datagouv_id} -> datagouv_id == bnlc_resource_id end)

    resource
  end

  def irve_resource do
    %{resource_id: irve_resource_id} = Map.fetch!(Application.fetch_env!(:transport, :consolidation), :irve)

    [resource] =
      irve_dataset()
      |> DB.Dataset.official_resources()
      |> Enum.filter(&match?(%DB.Resource{datagouv_id: ^irve_resource_id, format: "csv"}, &1))

    resource
  end

  def parkings_relais_resource do
    [resource] = parkings_relais_dataset() |> DB.Dataset.official_resources() |> Enum.filter(&(&1.format == "csv"))

    resource
  end

  def zfe_resource do
    [resource] = zfe_dataset() |> DB.Dataset.official_resources() |> Enum.filter(&(&1.title == "aires.geojson"))

    resource
  end

  defp base_consolidated_dataset_query(dataset_type, publisher, additional_fn \\ fn q -> q end) do
    publisher_label =
      case publisher do
        :datagouvfr -> datagouv_publisher_label()
        :transport -> transport_publisher_label()
      end

    DB.Dataset.base_query()
    |> preload(:resources)
    |> where([d], d.type == ^dataset_type and d.organization == ^publisher_label)
    |> additional_fn.()
    |> DB.Repo.one()
  end

  defp transport_publisher_label do
    Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)
  end

  defp datagouv_publisher_label do
    Application.fetch_env!(:transport, :datagouvfr_publisher_label)
  end
end
