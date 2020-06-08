defmodule Transport.Gtfs2Netexfr do
  @moduledoc """
  generate a netex for each resource that needs it

  This task only send demand for the generation of netex, the generation in itself will be done by the
  API server asynchronously and posted as communautary resource on data.gouv.
  """
  alias DB.{Repo, Resource}
  import Ecto.{Changeset, Query}
  require Logger

  @base_url "https://convertisseur.transport.data.gouv.fr"

  @spec convert_all(boolean()) :: any()
  def convert_all(force_update \\ false) do
    Logger.info("generating NeTEx for all GTFS")

    Resource
    |> where([r], not is_nil(r.url) and not is_nil(r.title) and r.format == "GTFS")
    # we don't want to generate a netex if there is already one
    |> where([r], fragment("? NOT IN (SELECT distinct(dataset_id) FROM resource WHERE format = 'NeTEx')", r.dataset_id))
    |> preload([:dataset])
    |> Repo.all()
    |> Stream.filter(fn r -> force_update || update_needed?(r) end)
    |> Stream.each(&generate_netex/1)
    |> Stream.run()

    Logger.info("all generation tasks have been launched")
  end

  @spec update_needed?(Resource.t()) :: boolean()
  defp update_needed?(%Resource{netex_conversion_latest_content_hash: nil}) do
    true
  end

  defp update_needed?(%Resource{
         netex_conversion_latest_content_hash: netex_conversion_latest_content_hash,
         content_hash: content_hash
       }) do
    # the resource needs to be converted is the netex have been generated with a content hash different
    netex_conversion_latest_content_hash != content_hash
  end

  @spec generate_netex(Resource.t()) :: :ok
  defp generate_netex(resource) do
    Logger.info("generating NeTEx for #{resource.dataset.title} - #{resource.title}")

    url = "#{@base_url}/gtfs2netexfr?url=#{resource.url}&datagouv_id=#{resource.dataset.datagouv_id}"

    Logger.debug(fn -> "converting resource #{resource.title}: #{url}" end)

    case HTTPoison.get(url) do
      {:ok, %{status_code: 200}} ->
        # Note: we only send a request to convert the GTFS to a NeTEx file, the generation is done asynchronously
        # the API server will post a communautary resource when available
        Logger.info("conversion ok for #{resource.id}")

        mark_as_converted(resource)

      {:ok, response} ->
        Logger.error("impossible to convert gtfs to NeTEx for resource #{resource.id}: #{inspect(response)}")

      {:error, error} ->
        Logger.error("impossible to convert gtfs to NeTEx for resource #{resource.id}: #{inspect(error)}")
    end
  end

  @spec mark_as_converted(Resource.t()) :: :ok
  defp mark_as_converted(resource) do
    # we set the netex_conversion_latest_content_hash to the current resource content hash
    resource
    |> change(netex_conversion_latest_content_hash: resource.content_hash)
    |> Repo.update()
  end
end
