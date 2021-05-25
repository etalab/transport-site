defmodule Transport.History.Backup do
  @moduledoc """
  Backup all ressources into s3 to have an history
  """
  import Ecto.Query
  require Logger
  alias Transport.History.Shared

  @spec backup_resources(boolean()) :: any()
  def backup_resources(force_update \\ false) do
    Logger.info("backuping the resources")

    DB.Resource
    |> where(
      [r],
      not is_nil(r.url) and not is_nil(r.title) and
        (r.format == "GTFS" or r.format == "NeTEx") and
        not r.is_community_resource
    )
    |> preload([:dataset])
    |> DB.Repo.all()
    |> Stream.map(fn r ->
      Logger.debug(fn -> "creating bucket #{Shared.resource_bucket_id(r)}" end)

      r
      |> Shared.resource_bucket_id()
      |> ExAws.S3.put_bucket("", %{acl: "public-read"})
      |> Transport.Wrapper.ExAWS.impl().request!()

      r
    end)
    |> Stream.filter(fn r -> force_update || needs_to_be_updated(r) end)
    |> Stream.each(&backup/1)
    |> Stream.run()
  end

  @spec modification_date(DB.Resource.t()) :: binary()
  defp modification_date(resource), do: resource.last_update || resource.last_import

  @spec needs_to_be_updated(DB.Resource.t()) :: boolean()
  defp needs_to_be_updated(resource) do
    backuped_resources = get_already_backuped_resources(resource)

    if Enum.empty?(backuped_resources) do
      true
    else
      already_there = Enum.find(backuped_resources, fn r -> r.content_hash == resource.content_hash end)

      if already_there != nil do
        false
      else
        max_last_modified =
          backuped_resources
          |> Enum.map(fn r -> r.updated_at end)
          |> Enum.max()

        max_last_modified < modification_date(resource)
      end
    end
  end

  @spec get_already_backuped_resources(DB.Resource.t()) :: [map()]
  defp get_already_backuped_resources(resource) do
    resource
    |> Shared.resource_bucket_id()
    |> ExAws.S3.list_objects(prefix: resource_title(resource))
    |> Transport.Wrapper.ExAWS.impl().stream!()
    |> Enum.map(fn o ->
      metadata = Shared.fetch_history_metadata(Shared.resource_bucket_id(resource), o.key)

      %{
        key: o.key,
        updated_at: metadata["updated-at"],
        content_hash: metadata["content-hash"]
      }
    end)
    |> Enum.to_list()
  end

  @spec resource_title(DB.Resource.t()) :: binary()
  defp resource_title(resource) do
    resource.title
    |> String.replace(" ", "_")
    |> String.replace("/", "_")
    |> String.replace("'", "_")
    # we use only ascii character for the title as cellar can be a tad strict
    |> Unidecode.decode()
    |> to_string
  end

  @spec maybe_put(map(), atom(), binary()) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec backup(DB.Resource.t()) :: :ok
  defp backup(resource) do
    Logger.info("backuping #{resource.dataset.title} - #{resource.title}")
    now = DateTime.utc_now() |> Timex.format!("%Y%m%dT%H%M%S", :strftime)

    meta =
      %{
        url: resource.url,
        title: resource_title(resource),
        format: resource.format,
        updated_at: modification_date(resource)
      }
      |> maybe_put(:start, resource.metadata["start_date"])
      |> maybe_put(:end, resource.metadata["end_date"])
      |> maybe_put(:content_hash, resource.content_hash)

    # NOTE: this call has a few drawbacks:
    # - redirects are not followed
    # - the whole resource is loaded in memory (could be streamed directly to S3 instead with Finch)
    case Transport.Wrapper.HTTPoison.impl().get(resource.url) do
      {:ok, %{status_code: 200, body: body}} ->
        resource
        |> Shared.resource_bucket_id()
        |> ExAws.S3.put_object(
          "#{resource_title(resource)}_#{now}",
          body,
          acl: "public-read",
          meta: meta
        )
        |> Transport.Wrapper.ExAWS.impl().request!()

      {:ok, response} ->
        Logger.error(inspect(response))

      {:error, error} ->
        Logger.error(inspect(error))
    end
  end
end
