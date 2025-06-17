defmodule Transport.ConsolidatedDataset do
  @moduledoc """
  A module to hold configuration of the datasets used in geodata queries and access them easily.
  """

  import Ecto.Query

  @config %{
    irve: %{dataset_type: "charging-stations", publisher: :datagouvfr},
    bnlc: %{dataset_type: "carpooling-areas", publisher: :transport},
    parkings_relais: %{dataset_type: "road-data", publisher: :transport},
    zfe: %{dataset_type: "road-data", publisher: :transport}
  }

  @available_datasets @config |> Map.keys()

  def geo_data_datasets do
    # For now, every consolidated dataset here has geographical features imported in the geo_data table
    @available_datasets
  end

  def dataset(name) when name in @available_datasets do
    publisher_id = @config |> get_in([name, :publisher]) |> publisher_id()
    dataset_type = @config |> get_in([name, :dataset_type])

    DB.Dataset.base_query()
    |> preload(:resources)
    |> where([d], d.type == ^dataset_type and d.organization_id == ^publisher_id)
    |> additional_ecto_query(name)
    |> DB.Repo.one!()
  end

  def resource(name) do
    [resource] =
      dataset(name)
      |> DB.Dataset.official_resources()
      |> filter_official_resources(name)

    resource
  end

  # This filter has been moved from previous code but is fragile
  defp additional_ecto_query(query, :parkings_relais) do
    query |> where([d], d.custom_title == "Base nationale des parcs relais")
  end

  defp additional_ecto_query(query, :zfe) do
    %{dataset_id: datagouv_id} = Map.fetch!(Application.fetch_env!(:transport, :consolidation), :zfe)
    query |> where([d], d.datagouv_id == ^datagouv_id)
  end

  defp additional_ecto_query(q, _), do: q

  # Following filters have been moved from previous code but are fragile
  # There should be a better and more unified way to be sure we find the right official resource
  defp filter_official_resources(resources, :bnlc) do
    Enum.filter(resources, fn %DB.Resource{datagouv_id: datagouv_id} -> datagouv_id == bnlc_resource_id() end)
  end

  defp filter_official_resources(resources, :irve) do
    irve_resource_id = irve_resource_id()
    Enum.filter(resources, &match?(%DB.Resource{datagouv_id: ^irve_resource_id, format: "csv"}, &1))
  end

  defp filter_official_resources(resources, :parkings_relais) do
    Enum.filter(resources, &(&1.format == "csv"))
  end

  defp filter_official_resources(resources, :zfe) do
    Enum.filter(resources, &(&1.title == "aires.geojson"))
  end

  defp publisher_id(:datagouvfr) do
    Application.fetch_env!(:transport, :datagouvfr_publisher_id)
  end

  defp publisher_id(:transport) do
    Application.fetch_env!(:transport, :datagouvfr_transport_publisher_id)
  end

  defp bnlc_resource_id do
    %{resource_id: bnlc_resource_id} = Map.fetch!(Application.fetch_env!(:transport, :consolidation), :bnlc)
    bnlc_resource_id
  end

  defp irve_resource_id do
    %{resource_id: irve_resource_id} = Map.fetch!(Application.fetch_env!(:transport, :consolidation), :irve)
    irve_resource_id
  end
end
