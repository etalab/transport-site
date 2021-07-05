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
    %{error: error_n, ok: ok_n} =
      list_orphan_community_resources()
      |> delete_resources()
      |> Enum.frequencies_by(fn {r, _} -> r end)

    Logger.info(
      "#{ok_n} community resources were successfully deleted because their parent resource didn't exist anymore"
    )

    if error_n > 0 do
      Logger.warn("#{error_n} community resources were listed as orphans but could not be deleted")
    end

    {:ok, ok_n}
  end

  @spec delete_resources([%{dataset_id: binary(), resource_id: binary()}]) :: [%{}]
  def delete_resources(resources) do
    resources
    |> Enum.map(fn %{dataset_id: dataset_id, resource_id: resource_id} ->
      Datagouvfr.Client.CommunityResources.delete(dataset_id, resource_id)
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
    |> Enum.map(fn r -> %{dataset_id: dataset.id, resource_id: r.id} end)
  end
end
