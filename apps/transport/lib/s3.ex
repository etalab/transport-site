defmodule Transport.S3 do
  @moduledoc """
  This module contains common code related to S3 object storage.
  """
  @buckets %{
    history: "resource-history"
  }

  def bucket_name(feature) do
    "transport-data-gouv-fr-#{Map.fetch!(@buckets, feature)}-#{Mix.env()}"
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
end
