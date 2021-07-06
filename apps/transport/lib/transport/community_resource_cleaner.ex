defmodule Transport.CommunityResourcesCleaner do
  @moduledoc """
  A module used to clean orphan community resources.
  When we (transport team) have created community resources from official resources, we need to delete
  the created resources if the parent official resource has been deleted from data.gouv.fr by its producer.
  For the moment, it only concerns GTFS resources (converted to geojson and NeTEx, but it could change in the
  future).
  """
  alias DB.{Dataset, Repo}
  import Ecto.Query
  require Logger

  @transport_publisher_label Application.get_env(
                               :transport,
                               :datagouvfr_transport_publisher_label
                             )

  def clean_community_resources do
    result =
      list_orphan_community_resources()
      |> delete_resources()
      |> Enum.frequencies_by(fn {r, _} -> r end)

    with %{error: error_n} <- result do
      Logger.warn("#{error_n} community resources were listed as orphans but could not be deleted")
    end

    ok_n = Map.get(result, :ok, 0)

    Logger.info(
      "#{ok_n} community resources were successfully deleted because their parent resource didn't exist anymore"
    )

    {:ok, ok_n}
  end

  @spec delete_resources([%{dataset_id: binary(), resource_id: binary()}]) :: [%{}]
  def delete_resources(resources) do
    resources
    |> Enum.map(fn %{
                     dataset_datagouv_id: dataset_datagouv_id,
                     resource_datagouv_id: resource_datagouv_id
                   } ->
      Datagouvfr.Client.CommunityResources.delete(dataset_datagouv_id, resource_datagouv_id)
    end)
  end

  def list_orphan_community_resources do
    Dataset
    |> preload(:resources)
    |> Repo.all()
    |> Enum.flat_map(fn d -> list_orphan_community_resources(d) end)
  end

  def list_orphan_community_resources(dataset) do
    resources_url =
      dataset.resources
      |> Enum.map(fn r -> r.url end)

    dataset.resources
    |> Enum.filter(fn r ->
      r.is_community_resource == true and
        r.community_resource_publisher == @transport_publisher_label
    end)
    |> Enum.reject(fn r -> resources_url |> Enum.member?(r.original_resource_url) end)
    |> Enum.map(fn r ->
      %{
        dataset_datagouv_id: dataset.datagouv_id,
        resource_datagouv_id: r.datagouv_id,
        dataset_id: dataset.id,
        resource_id: r.id
      }
    end)
  end
end
