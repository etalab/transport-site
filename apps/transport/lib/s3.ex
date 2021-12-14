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
    buckets_response = ExAws.S3.list_buckets() |> Transport.Wrapper.ExAWS.impl().request!()
    bucket_names = buckets_response.body.buckets |> Enum.map(& &1.name)

    bucket_name = bucket_name(feature)

    if not Enum.member?(bucket_names, bucket_name) do
      bucket_name
      |> ExAws.S3.put_bucket("", options)
      |> Transport.Wrapper.ExAWS.impl().request!()
    end
  end

  def upload_to_s3!(body, path) do
    Logger.debug("Uploading resource to #{path}")

    :history
    |> Transport.S3.bucket_name()
    |> ExAws.S3.put_object(
      path,
      body,
      acl: "public-read"
    )
    |> Transport.Wrapper.ExAWS.impl().request!()
  end
end
