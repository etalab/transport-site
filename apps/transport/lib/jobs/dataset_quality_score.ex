defmodule Transport.Jobs.DatasetQualityScore do
  @moduledoc """
  Computes quality scores for a dataset
  """
  import Ecto.Query

  def freshness_score(dataset_id) do
    resources =
      DB.Dataset.base_query()
      |> DB.Resource.join_dataset_with_resource()
      |> where([dataset: d, resource: r], d.id == ^dataset_id and not r.is_community_resource)
      |> select([resource: r], r)
      |> DB.Repo.all()

    current_dataset_freshness =
      resources
      |> Enum.map(&freshness(&1))
      |> Enum.reject(&is_nil(&1))
      |> average()

    current_dataset_freshness
  end

  defp average(e), do: Enum.sum(e) / Enum.count(e)

  def freshness(%{format: "GTFS", id: resource_id} = r) do
    IO.inspect(r)

    %{metadata: %{metadata: %{"start_date" => start_date, "end_date" => end_date}}} =
      DB.MultiValidation.resource_latest_validation(resource_id, Transport.Validators.GTFSTransport)

    start_date = Date.from_iso8601!(start_date)
    end_date = Date.from_iso8601!(end_date)

    today = Date.utc_today()

    freshness = if Date.compare(start_date, today) != :gt and Date.compare(today, end_date) != :gt, do: 1.0, else: 0.0
    IO.inspect("GTFS freshness is #{freshness}")
    freshness
  end

  def freshness(%{format: "gbfs", id: resource_id}) do
    freshness =
      case resource_latest_metadata(resource_id) do
        %{metadata: %{feed_timestamp_delay: feed_timestamp_delay}} -> gbfs_is_fresh(feed_timestamp_delay)
        _ -> nil
      end

    IO.inspect("GBFS freshness is #{freshness}")
    freshness
  end

  def freshness(%{format: "gtfs-rt", id: resource_id}) do
    freshness =
      case resource_latest_metadata(resource_id) do
        %{metadata: %{feed_timestamp_delay: feed_timestamp_delay}} -> gtfs_rt_is_fresh(feed_timestamp_delay)
        _ -> nil
      end

    IO.inspect("GTFS-RT freshness is #{freshness}")
    freshness
  end

  def freshness(%DB.Resource{}), do: nil

  @doc """
  5 minutes is the max delay allowed
  https://github.com/MobilityData/gbfs/blob/master/gbfs.md#data-latency
  """
  def gbfs_max_timestamp_delay, do: 5 * 60

  def gbfs_is_fresh(feed_timestamp_delay) do
    if feed_timestamp_delay < gbfs_max_timestamp_delay(), do: 1.0, else: 0.0
  end

  @doc """
  we allow a 5 minutes delay
  """
  def gtfs_rt_max_timestamp_delay, do: 5 * 60

  def gtfs_rt_is_fresh(feed_timestamp_delay) do
    if feed_timestamp_delay < gtfs_rt_max_timestamp_delay(), do: 1.0, else: 0.0
  end

  def resource_latest_metadata(resource_id) do
    DB.ResourceMetadata.base_query()
    |> where([metadata: m], m.resource_id == ^resource_id)
    |> distinct([metadata: m], m.resource_id)
    |> order_by([metadata: m], desc: m.inserted_at)
    |> DB.Repo.one()
  end
end
