defmodule Transport.Jobs.Backfill.RemoveGTFSRTSnapshots do
  @moduledoc """
  Delete GTFS-RT files that have been stored in the object storage with the v1 validation.
  """
  use Oban.Worker
  @bucket_feature :history

  @impl true
  def perform(%{}) do
    @bucket_feature
    |> Transport.S3.bucket_name()
    |> ExAws.S3.list_objects()
    |> Transport.Wrapper.ExAWS.impl().stream!()
    # Sample file key:
    # 0fbf9dc8-d2db-405d-ade4-fdd04a6f8272/0fbf9dc8-d2db-405d-ade4-fdd04a6f8272.20220530.122958.288342.bin
    # See https://github.com/etalab/transport-site/blob/3c870a42d0e6212f181cc69818755b5871f7f62c/apps/transport/lib/jobs/gtfs_rt_validation_job.ex#L207-L211
    |> Stream.filter(&String.match?(&1.key, ~r/\.2022(\d){4}\.(\d){6}\.(\d){6}\.bin$/))
    |> Stream.map(& &1.key)
    |> Stream.each(&Transport.S3.delete_object!(@bucket_feature, &1))
    |> Stream.run()
  end
end
