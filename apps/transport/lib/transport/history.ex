defmodule Transport.History do
  @moduledoc """
  backup all ressources into s3 to have an history
  """
  alias ExAws.S3
  alias DB.{Dataset, Repo, Resource}
  import Ecto.{Query}
  require Logger

  def backup_resources(force_update \\ false) do
    if Application.get_env(:ex_aws, :access_key_id) == nil ||
         Application.get_env(:ex_aws, :secret_access_key) == nil do
      Logger.warn("no cellar credential set, we skip resource backup")
    else
      Logger.info("backuping the resources")

      Resource
      |> where(
        [r],
        not is_nil(r.url) and not is_nil(r.title) and
          (r.format == "GTFS" or r.format == "netex")
      )
      |> preload([:dataset])
      |> Repo.all()
      |> Stream.map(fn r ->
        Logger.debug(fn -> "creating bucket #{bucket_id(r)}" end)

        r
        |> bucket_id()
        |> S3.put_bucket("", %{acl: "public-read"})
        |> ExAws.request!()

        r
      end)
      |> Stream.filter(fn r -> force_update || needs_to_be_updated(r) end)
      |> Stream.each(&backup/1)
      |> Stream.run()
    end
  end

  defp modification_date(resource) do
    resource.last_update || resource.last_import
  end

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

  def bucket_id(resource) do
    Dataset.history_bucket_id(resource.dataset)
  end

  defp get_already_backuped_resources(resource) do
    resource
    |> bucket_id()
    |> S3.list_objects(prefix: resource_title(resource))
    |> ExAws.stream!()
    |> Enum.map(fn o ->
      metadata = Dataset.fetch_history_metadata(bucket_id(resource), o.key)

      %{
        key: o.key,
        updated_at: metadata["updated-at"],
        content_hash: metadata["content-hash"]
      }
    end)
    |> Enum.to_list()
  end

  defp resource_title(resource) do
    resource.title
    |> String.replace(" ", "_")
    |> String.replace("/", "_")
    |> String.replace("'", "_")
    # we use only ascii character for the title as cellar can be a tad strict
    |> Unidecode.decode()
    |> to_string
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

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

    case HTTPoison.get(resource.url) do
      {:ok, %{status_code: 200, body: body}} ->
        resource
        |> bucket_id()
        |> S3.put_object(
          "#{resource_title(resource)}_#{now}",
          body,
          acl: "public-read",
          meta: meta
        )
        |> ExAws.request!()

      {:ok, response} ->
        Logger.error(inspect(response))

      {:error, error} ->
        Logger.error(inspect(error))
    end
  end
end
