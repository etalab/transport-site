defmodule Transport.S3 do
  @moduledoc """
  This module contains common code related to S3 object storage.
  """
  require Logger

  @spec bucket_name(atom()) :: binary()
  def bucket_name(feature) do
    config = Application.fetch_env!(:transport, :s3_buckets)
    "transport-data-gouv-fr-#{Map.fetch!(config, feature)}"
  end

  @spec permanent_url(atom(), binary()) :: binary()
  def permanent_url(feature, path \\ "") do
    host = :io_lib.format(Application.fetch_env!(:ex_aws, :cellar_url), [bucket_name(feature)])
    host |> to_string() |> URI.merge(path) |> URI.to_string()
  end

  @spec all_permanent_urls_domains() :: [binary()]
  def all_permanent_urls_domains do
    :transport
    |> Application.fetch_env!(:s3_buckets)
    |> Map.keys()
    |> Enum.map(&Transport.S3.permanent_url(&1, "/"))
  end

  @spec bucket_names() :: [binary()]
  def bucket_names do
    buckets_response = ExAws.S3.list_buckets() |> Transport.Wrapper.ExAWS.impl().request!()
    buckets_response.body.buckets |> Enum.map(& &1.name)
  end

  @spec delete_object!(atom(), binary()) :: any()
  def delete_object!(feature, path) do
    bucket = bucket_name(feature)

    bucket |> ExAws.S3.delete_object(path) |> Transport.Wrapper.ExAWS.impl().request!()
  end

  @spec stream_to_s3!(atom(), binary(), binary()) :: any()
  def stream_to_s3!(feature, local_path, upload_path) do
    local_path
    |> ExAws.S3.Upload.stream_file()
    |> ExAws.S3.upload(Transport.S3.bucket_name(feature), upload_path, acl: "public-read")
    |> Transport.Wrapper.ExAWS.impl().request!()
  end

  @spec upload_to_s3!(atom(), binary(), binary()) :: any()
  def upload_to_s3!(feature, body, path) do
    Logger.debug("Uploading file to #{path}")

    feature
    |> Transport.S3.bucket_name()
    |> ExAws.S3.put_object(
      path,
      body,
      acl: "public-read"
    )
    |> Transport.Wrapper.ExAWS.impl().request!()
  end
end
