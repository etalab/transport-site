defmodule Transport.ConsolidatedDataset do
  @moduledoc """
  A module to hold configuration of the datasets used in geodata queries and access them easily.
  """

  import Ecto.Query

  def bnlc_dataset do
    base_consolidated_dataset_query("carpooling-areas", :transport)
  end

  def bnlc_resource do
    filter_fn = fn resources ->
      Enum.filter(resources, fn %DB.Resource{datagouv_id: datagouv_id} -> datagouv_id == bnlc_resource_id() end)
    end

    get_resource(bnlc_dataset(), filter_fn)
  end

  def irve_dataset do
    base_consolidated_dataset_query("charging-stations", :datagouvfr)
  end

  def irve_resource do
    filter_fn = fn resources ->
      irve_resource_id = irve_resource_id()
      Enum.filter(resources, &match?(%DB.Resource{datagouv_id: ^irve_resource_id, format: "csv"}, &1))
    end

    get_resource(irve_dataset(), filter_fn)
  end

  def parkings_relais_dataset do
    additional_fn = fn query ->
      query |> where([d], d.custom_title == "Base nationale des parcs relais")
    end

    base_consolidated_dataset_query("private-parking", :transport, additional_fn)
  end

  def parkings_relais_resource do
    filter_fn = fn resources ->
      Enum.filter(resources, &(&1.format == "csv"))
    end

    get_resource(parkings_relais_dataset(), filter_fn)
  end

  def zfe_dataset do
    base_consolidated_dataset_query("low-emission-zones", :transport)
  end

  def zfe_resource do
    filter_fn = fn resources ->
      Enum.filter(resources, &(&1.title == "aires.geojson"))
    end

    get_resource(zfe_dataset(), filter_fn)
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

  def get_resource(nil, _filter_fn) do
    nil
  end

  def get_resource(dataset, filter_fn) do
    [resource] = dataset |> DB.Dataset.official_resources() |> filter_fn.()

    resource
  end

  defp transport_publisher_label do
    Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)
  end

  defp datagouv_publisher_label do
    Application.fetch_env!(:transport, :datagouvfr_publisher_label)
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
