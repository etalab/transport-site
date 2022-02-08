defmodule Transport.S3 do
  @moduledoc """
  This module contains common code related to S3 object storage.
  """
  require Logger

  def bucket_name(feature) do
    config = Application.fetch_env!(:transport, :s3_buckets)
    "transport-data-gouv-fr-#{Map.fetch!(config, feature)}"
  end

  def permanent_url(feature, path \\ "") do
    host = :io_lib.format(Application.fetch_env!(:ex_aws, :cellar_url), [bucket_name(feature)])
    host |> to_string() |> URI.merge(path) |> URI.to_string()
  end

  def create_bucket_if_needed!(feature, options \\ %{acl: "public-read"}) do
    bucket_name = bucket_name(feature)

    if not Enum.member?(bucket_names(), bucket_name) do
      bucket_name
      |> ExAws.S3.put_bucket("", options)
      |> Transport.Wrapper.ExAWS.impl().request!()
    end
  end

  def bucket_names do
    buckets_response = ExAws.S3.list_buckets() |> Transport.Wrapper.ExAWS.impl().request!()
    buckets_response.body.buckets |> Enum.map(& &1.name)
  end

  def delete_object(feature, path) do
    bucket = bucket_name(feature)

    bucket |> ExAws.S3.delete_object(path) |> Transport.Wrapper.ExAWS.impl().request!()
  end

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
