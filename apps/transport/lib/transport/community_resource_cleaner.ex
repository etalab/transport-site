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
    orphan_resources = list_orphan_community_resources()
    n = delete_resources(orphan_resources)

    Logger.info(
      "#{n} community resources were deleted because their parent resource didn't exist anymore"
    )

    {:ok, n}
  end

  def delete_resources(res) do
    res |> Enum.count()
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
    |> Enum.map(fn r -> r.id end)
  end
end
