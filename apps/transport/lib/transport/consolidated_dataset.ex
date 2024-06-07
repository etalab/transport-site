defmodule Transport.ConsolidatedDataset do
  @moduledoc """
  A module to hold configuration of the datasets used in geodata queries and access them easily.
  """

  import Ecto.Query

  @config %{
    irve: %{dataset_type: "charging-stations", publisher: :datagouvfr},
    bnlc: %{dataset_type: "carpooling-areas", publisher: :transport},
    parkings_relais: %{dataset_type: "private-parking", publisher: :transport},
    zfe: %{dataset_type: "low-emission-zones", publisher: :transport}
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
    |> DB.Repo.one()
  end

  def additional_ecto_query(query, :parkings_relais) do
    query |> where([d], d.custom_title == "Base nationale des parcs relais")
  end

  def additional_ecto_query(q, _), do: q

  def bnlc_resource do
    filter_fn = fn resources ->
      Enum.filter(resources, fn %DB.Resource{datagouv_id: datagouv_id} -> datagouv_id == bnlc_resource_id() end)
    end

    get_resource(dataset(:bnlc), filter_fn)
  end

  def irve_resource do
    filter_fn = fn resources ->
      irve_resource_id = irve_resource_id()
      Enum.filter(resources, &match?(%DB.Resource{datagouv_id: ^irve_resource_id, format: "csv"}, &1))
    end

    get_resource(dataset(:irve), filter_fn)
  end

  def parkings_relais_resource do
    filter_fn = fn resources ->
      Enum.filter(resources, &(&1.format == "csv"))
    end

    get_resource(dataset(:parkings_relais), filter_fn)
  end

  def zfe_resource do
    filter_fn = fn resources ->
      Enum.filter(resources, &(&1.title == "aires.geojson"))
    end

    get_resource(dataset(:zfe), filter_fn)
  end

  def get_resource(nil, _filter_fn) do
    nil
  end

  def get_resource(dataset, filter_fn) do
    [resource] = dataset |> DB.Dataset.official_resources() |> filter_fn.()

    resource
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
