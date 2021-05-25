defmodule Transport.History do
  @moduledoc """
  Tooling related to backup and restore resources from S3/Cellar.
  """

  defmodule Shared do
    @moduledoc """
    This module contains common code which is shared
    between various parts of the history system.
    """
    @spec dataset_bucket_id(DB.Dataset.t()) :: binary()
    def dataset_bucket_id(%DB.Dataset{} = dataset) do
      "dataset-#{dataset.datagouv_id}"
    end

    @spec resource_bucket_id(Resource.t()) :: binary()
    def resource_bucket_id(%DB.Resource{} = resource), do: dataset_bucket_id(resource.dataset)

    @spec fetch_history_metadata(binary(), binary()) :: map()
    def fetch_history_metadata(bucket, obj_key) do
      bucket
      |> ExAws.S3.head_object(obj_key)
      |> Transport.Wrapper.ExAWS.impl().request!()
      |> Map.get(:headers)
      |> Map.new(fn {k, v} -> {String.replace(k, "x-amz-meta-", ""), v} end)
      |> Map.take(["format", "title", "start", "end", "updated-at", "content-hash"])
    end
  end

  defmodule Fetcher do
    @moduledoc """
    Boundary for all retrieval resources' history, with an indirection to
    the default implementation.
    """
    @callback history_resources(DB.Dataset.t()) :: [map()]

    def impl, do: Application.get_env(:transport, :history_impl, Fetcher.S3)

    def history_resources(%DB.Dataset{} = dataset), do: impl().history_resources(dataset)
  end

  defmodule Fetcher.Mock do
    @behaviour Fetcher

    @moduledoc """
    A default implementation returning an empty history, useful as a default
    implementation for tests unrelated to history.
    """

    def history_resources(%DB.Dataset{}), do: []
  end

  defmodule Fetcher.S3 do
    @behaviour Fetcher

    @moduledoc """
    The S3-backed implementation of history fetching.
    """

    require Logger

    @spec history_resources(DB.Dataset.t()) :: [map()]
    def history_resources(%DB.Dataset{} = dataset) do
      bucket = Transport.History.Shared.dataset_bucket_id(dataset)

      bucket
      |> ExAws.S3.list_objects()
      |> Transport.Wrapper.ExAWS.impl().stream!()
      |> Enum.to_list()
      |> Enum.map(fn f ->
        metadata = Shared.fetch_history_metadata(bucket, f.key)

        is_current =
          dataset.resources
          |> Enum.map(fn r -> r.content_hash end)
          |> Enum.any?(fn hash -> !is_nil(hash) && metadata["content-hash"] == hash end)

        %{
          name: f.key,
          href: history_resource_path(bucket, f.key),
          metadata: metadata,
          is_current: is_current,
          last_modified: f.last_modified
        }
      end)
      |> Enum.sort_by(fn f -> f.last_modified end, &Kernel.>=/2)
    rescue
      e in ExAws.Error ->
        Logger.error("error while accessing the S3 bucket: #{inspect(e)}")
        []
    end

    defp cellar_host, do: Application.get_env(:ex_aws, :s3)[:host]
    defp cellar_scheme, do: Application.get_env(:ex_aws, :s3)[:scheme]

    @spec history_resource_path(binary(), binary()) :: binary()
    defp history_resource_path(bucket, name), do: Path.join([cellar_scheme(), bucket <> "." <> cellar_host(), name])
  end

  defmodule Backup do
    @moduledoc """
    Backup all ressources into s3 to have an history
    """
    import Ecto.Query
    require Logger

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

    @spec modification_date(Resource.t()) :: binary()
    defp modification_date(resource), do: resource.last_update || resource.last_import

    @spec needs_to_be_updated(Resource.t()) :: boolean()
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

    @spec get_already_backuped_resources(Resource.t()) :: [map()]
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

    @spec resource_title(Resource.t()) :: binary()
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

    @spec backup(Resource.t()) :: :ok
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
end
