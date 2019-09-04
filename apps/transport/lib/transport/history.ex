defmodule Transport.History do
  @moduledoc """
  backup all ressources into s3 to have an history
  """
  alias ExAws.S3
  alias Transport.{Repo, Resource}
  import Ecto.{Query}
  require Logger

  def backup_resources() do
    if Application.get_env(:ex_aws, :access_key_id) == nil
      || Application.get_env(:ex_aws, :secret_access_key) == nil do
      # if the cellar credential are missing, we skip the whole history backup
        Logger.warn("no cellar credential set, we skip to resource backup")
    else
      resources_to_backup = Resource
      |> where([r], not is_nil(r.url) and not is_nil(r.title) and (ilike(r.format, "GTFS") or ilike(r.format, "netex")))
      |> preload([:dataset])
      |> Repo.all()

      for r <- resources_to_backup do
        Logger.info("creating bucket #{bucket_id(r)}")
        S3.put_bucket(bucket_id(r), "", %{acl: "public-read"}) |> ExAws.request!
        if needs_to_be_updated(r) do
          Logger.info("backuping #{r.dataset.title} - #{r.title}")
          backup(r)
        else
          Logger.info("resource already backuped: #{r.dataset.title} - #{r.title}")
        end
      end
  end

  defp needs_to_be_updated(resource) do
    backuped_resources = get_already_backuped_resources(resource)

    case backuped_resources do
      [] ->
        true
      _ ->
        max_last_modified = backuped_resources |> Enum.max_by(fn r -> r.last_modified end)
        date = resource.last_update || resource.last_import
        modification_date = NaiveDateTime.from_iso8601(date)
        max_last_modified < modification_date
    end
  end

  defp bucket_id(r), do: "dataset-#{r.dataset.datagouv_id}"

  defp get_already_backuped_resources(resource) do
    resource
    |> bucket_id()
    |> S3.list_objects(prefix: resource_title(resource))
    |> ExAws.stream!
    |> Enum.to_list
  end

  defp resource_title(resource) do
    resource.title
    |> String.replace(" ", "_")
    |> String.replace("/", "_")
    |> String.replace("'", "_")
    # we use only ascii character for the title as cellar can be a tad strict
    |> Unidecode.decode
    |> to_string
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp backup(resource) do
    now = DateTime.utc_now() |> Timex.format!("%Y%m%dT%H%M%S", :strftime)
    meta = %{
      url: resource.url,
      title: resource_title(resource),
      format: resource.format,
      }
      |> maybe_put(:start, resource.metadata["start_date"])
      |> maybe_put(:end, resource.metadata["end_date"])

    case HTTPoison.get(resource.url) do
      {:ok, %{status_code: 200, body: body}} ->
        resource
        |> bucket_id()
        |> S3.put_object(
            "#{resource_title(resource)}_#{now}",
            body,
            acl: "public-read",
            meta: meta)
        |> ExAws.request!
      {:ok, response} -> Logger.error(inspect(response))
      {:error, error} -> Logger.error(inspect(error))
    end
  end

end
