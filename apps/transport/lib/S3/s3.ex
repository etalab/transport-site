defmodule Transport.S3 do
  @moduledoc """
  This module contains common code related to S3 object storage.
  """
  require Logger
  @type bucket_feature :: :history | :on_demand_validation | :gtfs_diff | :logos | :aggregates

  @spec bucket_name(bucket_feature()) :: binary()
  def bucket_name(feature) do
    config = Application.fetch_env!(:transport, :s3_buckets)
    "transport-data-gouv-fr-#{Map.fetch!(config, feature)}"
  end

  @spec permanent_url(bucket_feature(), binary()) :: binary()
  def permanent_url(feature, path \\ "") do
    base_url = :io_lib.format(Application.fetch_env!(:ex_aws, :cellar_url), [bucket_name(feature)]) |> to_string()

    if String.length(path) > 0 do
      base_url |> URI.parse() |> URI.append_path("/" <> path) |> URI.to_string()
    else
      base_url
    end
  end

  @spec bucket_names() :: [binary()]
  def bucket_names do
    buckets_response = ExAws.S3.list_buckets() |> Transport.Wrapper.ExAWS.impl().request!()
    buckets_response.body.buckets |> Enum.map(& &1.name)
  end

  @spec delete_object!(bucket_feature(), binary()) :: any()
  def delete_object!(feature, path) do
    bucket = bucket_name(feature)

    bucket |> ExAws.S3.delete_object(path) |> Transport.Wrapper.ExAWS.impl().request!()
  end

  @spec stream_to_s3!(bucket_feature(), binary(), binary(), acl: atom(), cache_control: binary()) :: any()
  def stream_to_s3!(feature, local_path, upload_path, options \\ []) do
    Logger.debug("Streaming #{local_path} to #{upload_path}")
    options = Keyword.validate!(options, [:cache_control, {:acl, :private}])

    local_path
    |> ExAws.S3.Upload.stream_file()
    |> ExAws.S3.upload(Transport.S3.bucket_name(feature), upload_path, options)
    |> Transport.Wrapper.ExAWS.impl().request!()
  end

  @spec download_file(bucket_feature(), binary(), binary()) :: any()
  def download_file(feature, remote_path, local_path) do
    Logger.debug("Downloading #{remote_path} to #{local_path}")

    feature
    |> Transport.S3.bucket_name()
    |> ExAws.S3.download_file(remote_path, local_path)
    |> Transport.Wrapper.ExAWS.impl().request!()
  end

  @spec get_object(bucket_feature(), binary()) :: binary()
  def get_object(feature, remote_path) do
    Logger.debug("Getting object from #{remote_path} into RAM")

    feature
    |> Transport.S3.bucket_name()
    |> ExAws.S3.get_object(remote_path)
    |> Transport.Wrapper.ExAWS.impl().request!()
  end

  @spec remote_copy_file!(bucket_feature(), binary(), binary()) :: any()
  def remote_copy_file!(feature, remote_path_src, remote_path_dest) do
    bucket = Transport.S3.bucket_name(feature)

    ExAws.S3.put_object_copy(bucket, remote_path_dest, bucket, remote_path_src)
    |> Transport.Wrapper.ExAWS.impl().request!()
  end
end
