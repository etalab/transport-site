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
