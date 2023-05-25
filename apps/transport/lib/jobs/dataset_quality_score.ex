defmodule Transport.Jobs.DatasetQualityScore do
  @moduledoc """
  Computes quality scores for a dataset
  """
  import Ecto.Query

  def save_dataset_freshness_score(dataset_id) do
    score = dataset_freshness_score(dataset_id)

    %DB.DatasetScore{dataset_id: dataset_id, topic: "freshness", score: score, timestamp: DateTime.utc_now()}
    |> DB.Repo.insert()
  end

  def dataset_freshness_score(dataset_id) do
    today_score = current_dataset_freshness(dataset_id)
    last_dataset_freshness = last_dataset_freshness(dataset_id)
    alpha = 0.9

    case last_dataset_freshness do
      # Exponential smoothing
      # https://en.wikipedia.org/wiki/Exponential_smoothing
      %{score: previous_score} -> alpha * previous_score + (1.0 - alpha) * today_score
      nil -> today_score
    end
  end

  def last_dataset_freshness(dataset_id) do
    DB.DatasetScore.base_query()
    |> where([ds], ds.dataset_id == ^dataset_id and ds.topic == "freshness")
    |> order_by([ds], desc: ds.timestamp)
    |> limit(1)
    |> DB.Repo.one()
  end

  def current_dataset_freshness(dataset_id) do
    resources =
      DB.Dataset.base_query()
      |> DB.Resource.join_dataset_with_resource()
      |> where([dataset: d, resource: r], d.id == ^dataset_id and not r.is_community_resource)
      |> select([resource: r], r)
      |> DB.Repo.all()

    current_dataset_freshness =
      resources
      |> Enum.map(&resource_freshness(&1))
      |> Enum.reject(&is_nil(&1))
      |> average()

    current_dataset_freshness
  end

  defp average([]), do: nil
  defp average(e), do: Enum.sum(e) / Enum.count(e)

  def resource_freshness(%{format: "GTFS", id: resource_id}) do
    resource_id
    |> DB.MultiValidation.resource_latest_validation(Transport.Validators.GTFSTransport)
    |> case do
      %{metadata: %{metadata: %{"start_date" => start_date, "end_date" => end_date}}} ->
        start_date = Date.from_iso8601!(start_date)
        end_date = Date.from_iso8601!(end_date)

        today = Date.utc_today()

        freshness =
          if Date.compare(start_date, today) != :gt and Date.compare(today, end_date) != :gt, do: 1.0, else: 0.0

        IO.inspect("GTFS freshness is #{freshness}")
        freshness

      _ ->
        nil
    end
  end

  def resource_freshness(%{format: "gbfs", id: resource_id}) do
    freshness =
      case resource_last_metadata_from_today(resource_id) do
        %{metadata: %{"feed_timestamp_delay" => feed_timestamp_delay}} -> gbfs_feed_freshness(feed_timestamp_delay)
        _ -> nil
      end

    IO.inspect("GBFS freshness is #{freshness}")
    freshness
  end

  def resource_freshness(%{format: "gtfs-rt", id: resource_id}) do
    freshness =
      case resource_last_metadata_from_today(resource_id) do
        %{metadata: %{"feed_timestamp_delay" => feed_timestamp_delay}} -> gtfs_rt_feed_freshness(feed_timestamp_delay)
        _ -> nil
      end

    IO.inspect("GTFS-RT freshness is #{freshness}")
    freshness
  end

  def resource_freshness(%DB.Resource{}), do: nil

  @doc """
  5 minutes is the max delay allowed
  https://github.com/MobilityData/gbfs/blob/master/gbfs.md#data-latency
  """
  def gbfs_max_timestamp_delay, do: 5 * 60

  def gbfs_feed_freshness(feed_timestamp_delay) do
    if feed_timestamp_delay < gbfs_max_timestamp_delay(), do: 1.0, else: 0.0
  end

  @doc """
  we allow a 5 minutes delay
  """
  def gtfs_rt_max_timestamp_delay, do: 5 * 60

  def gtfs_rt_feed_freshness(feed_timestamp_delay) do
    if feed_timestamp_delay < gtfs_rt_max_timestamp_delay(), do: 1.0, else: 0.0
  end

  def resource_last_metadata_from_today(resource_id) do
    DB.ResourceMetadata.base_query()
    |> where([metadata: m], m.resource_id == ^resource_id and fragment("date(?) = CURRENT_DATE", m.inserted_at))
    |> distinct([metadata: m], m.resource_id)
    |> order_by([metadata: m], desc: m.inserted_at)
    |> DB.Repo.one()
    |> IO.inspect()
  end
end
