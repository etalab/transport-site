defmodule Transport.History.Shared do
  @moduledoc """
  This module contains common code which is shared
  between various parts of the history system.
  """
  @spec dataset_bucket_id(DB.Dataset.t()) :: binary()
  def dataset_bucket_id(%DB.Dataset{} = dataset) do
    "dataset-#{dataset.datagouv_id}"
  end

  @spec resource_bucket_id(DB.Resource.t()) :: binary()
  def resource_bucket_id(%DB.Resource{} = resource), do: dataset_bucket_id(resource.dataset)

  @spec list_objects(binary(), binary()) :: Enum.t()
  def list_objects(bucket, prefix \\ "") do
    bucket
    |> ExAws.S3.list_objects(prefix: prefix)
    |> Transport.Wrapper.ExAWS.impl().stream!()
    # Make sure objects belong to our organisation
    |> Stream.filter(fn object ->
      String.ends_with?(object[:owner][:display_name], Application.fetch_env!(:ex_aws, :cellar_organisation_id))
    end)
  end

  @spec fetch_history_metadata(binary(), binary()) :: map()
  def fetch_history_metadata(bucket, obj_key) do
    bucket
    |> ExAws.S3.head_object(obj_key)
    |> Transport.Wrapper.ExAWS.impl().request!()
    |> Map.get(:headers)
    |> Map.new(fn {k, v} -> {String.replace(k, "x-amz-meta-", ""), v} end)
    |> Map.take(["format", "title", "start", "end", "updated-at", "content-hash", "url"])
  end
end
