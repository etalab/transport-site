defmodule Transport.GBFSMetadata do
  @moduledoc """
  Compute and store metadata for GBFS resources.
  """
  alias DB.{Dataset, Repo, Resource}
  import Ecto.Query
  require Logger

  @doc """
  It is a bit of work, currently, to extract the list of `gbfs.json` endpoints,
  for instance because `format` is not enough alone to filter them.

  See https://github.com/etalab/transport-site/issues/1891#issuecomment-958888421 for some background.
  """
  def gbfs_feeds_query do
    Resource
    |> join(:inner, [r], d in Dataset, on: r.dataset_id == d.id)
    |> where([_r, d], d.type == "bike-scooter-sharing" and d.is_active)
    |> where([r, _d], like(r.url, "%gbfs.json") or r.format == "gbfs")
    |> where([r, _d], not fragment("? ~ ?", r.url, "station|free_bike"))
  end

  def set_gbfs_feeds_metadata do
    resources = gbfs_feeds_query() |> Repo.all()

    Logger.info("Fetching details about #{Enum.count(resources)} GBFS feeds")

    resources
    |> Stream.map(fn resource ->
      Logger.info("Fetching GBFS metadata for #{resource.url} (##{resource.id})")
      changeset = Resource.changeset(resource, %{format: "gbfs", metadata: compute_feed_metadata(resource)})
      Repo.update!(changeset)
    end)
    |> Stream.run()
  end

  def compute_feed_metadata(%Resource{url: url}), do: compute_feed_metadata(url)

  def compute_feed_metadata(url) when is_binary(url),
    do: Transport.Shared.GBFSMetadata.Wrapper.compute_feed_metadata(url, TransportWeb.Endpoint.url())

  def validator_name(), do: "GBFS-Validator"
end
