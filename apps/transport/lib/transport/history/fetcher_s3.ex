defmodule Transport.History.Fetcher.S3 do
  @behaviour Transport.History.Fetcher

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
      metadata = Transport.History.Shared.fetch_history_metadata(bucket, f.key)

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
    # NOTE: this will go away when https://github.com/etalab/transport_deploy/issues/31 is taken care of
    e in ExAws.Error ->
      Logger.error("error while accessing the S3 bucket: #{inspect(e)}")
      []
  end

  defp cellar_host, do: Application.get_env(:ex_aws, :s3)[:host]
  defp cellar_scheme, do: Application.get_env(:ex_aws, :s3)[:scheme]

  @spec history_resource_path(binary(), binary()) :: binary()
  defp history_resource_path(bucket, name), do: Path.join([cellar_scheme(), bucket <> "." <> cellar_host(), name])
end
