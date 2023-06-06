defmodule Transport.Jobs.DatasetQualityScoreDispatcher do
  @moduledoc """
  Computes quality scores for a dataset
  """
  use Oban.Worker, unique: [period: 60 * 60 * 20], max_attempts: 1
  import Ecto.Query

  @impl Oban.Worker
  def perform(_job) do
    DB.Dataset.base_query()
    |> DB.Repo.all()
    |> Enum.map(fn dataset ->
      %{dataset_id: dataset.id} |> Transport.Jobs.DatasetQualityScore.new()
    end)
    |> Oban.insert_all()

    :ok
  end
end

defmodule Transport.Jobs.DatasetQualityScore do
  @moduledoc """
  Computes quality scores for a dataset
  """
  use Oban.Worker, unique: [period: 60 * 60 * 20], max_attempts: 1
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"dataset_id" => dataset_id}}) do
    save_dataset_freshness_score(dataset_id)
    :ok
  end

  @spec save_dataset_freshness_score(integer) :: DB.DatasetScore.t() | nil
  def save_dataset_freshness_score(dataset_id) do
    %{score: score, details: details} = dataset_freshness_score(dataset_id)

    %DB.DatasetScore{}
    |> DB.DatasetScore.changeset(%{
      dataset_id: dataset_id,
      topic: "freshness",
      score: score,
      timestamp: DateTime.utc_now(),
      details: details
    })
    |> case do
      %{valid?: true} = c ->
        DB.Repo.insert(c)

      c ->
        Sentry.capture_message(
          "Dataset quality score entry is incorrect",
          extra: %{dataset_id: dataset_id, error_reason: inspect(c)}
        )

        nil
    end
  end

  @spec dataset_freshness_score(integer) :: %{details: map, score: nil | float}
  @doc """
  dataset "freshness" is the answer to the question:
  "When the data was downloaded, was it up-to-date?"
  To give a score, we proceed this way:
  - get the dataset's current resources
  - for each resource, give it a score
  - we compute an average of those scores to get a score at the dataset level
  - that score is averaged with the dataset's last computed score, using exponential smoothing
  (see the function exp_smoothing below). This allows a score to reflect not only the current
  dataset situation but also past situations. Typically, a dataset that had outdated resources
  for the past year, but only up-to-date resources today is expected to have a low freshness score.
  The interest of exponential smoothing is to give past scores an increasingly small weight as time
  passes. To have a good score, a dataset must have up-to-date resources every day.
  """
  def dataset_freshness_score(dataset_id) do
    %{dataset_freshness: today_score, details: details} = current_dataset_freshness(dataset_id)
    last_dataset_freshness = last_dataset_freshness(dataset_id)

    computed_score =
      case last_dataset_freshness do
        %{score: previous_score} when is_float(previous_score) ->
          exp_smoothing(previous_score, today_score)

        _ ->
          today_score
      end

    %{score: computed_score, details: build_details(details, last_dataset_freshness)}
  end

  @doc """
  build the details map to explain the score computation

  iex> build_details(%{resources: [%{resource_id: 1}]}, %{score: 1.0})
  %{resources: [%{resource_id: 1}], previous_score: 1.0}

  iex> build_details(%{resources: [%{resource_id: 1}]}, nil)
  %{resources: [%{resource_id: 1}], previous_score: nil}

  iex> build_details(%{resources: [%{resource_id: 1}]}, %{score: nil})
  %{resources: [%{resource_id: 1}], previous_score: nil}

  iex> build_details(nil, %{score: 1.0})
  %{previous_score: 1.0}

  """
  def build_details(%{} = details, %{score: previous_score}) when is_float(previous_score) do
    Map.merge(details, %{previous_score: previous_score})
  end

  def build_details(%{} = details, _last_dataset_freshness) do
    Map.merge(details, %{previous_score: nil})
  end

  def build_details(_details, last_dataset_freshness) do
    build_details(%{}, last_dataset_freshness)
  end

  @spec exp_smoothing(float, float) :: float
  @doc """
  Exponential smoothing. See https://en.wikipedia.org/wiki/Exponential_smoothing

  iex> exp_smoothing(0.5, 1)
  0.55
  """
  def exp_smoothing(previous_score, today_score) do
    alpha = 0.9
    alpha * previous_score + (1.0 - alpha) * today_score
  end

  def last_dataset_freshness(dataset_id) do
    # if a previous score exists but is too old, it is not used
    max_last_score_age_days = 7

    DB.DatasetScore.base_query()
    |> where(
      [ds],
      ds.dataset_id == ^dataset_id and ds.topic == "freshness" and not is_nil(ds.score) and
        fragment(
          "DATE(?) < CURRENT_DATE AND DATE(?) > CURRENT_DATE - ?::integer",
          ds.timestamp,
          ds.timestamp,
          ^max_last_score_age_days
        )
    )
    |> order_by([ds], desc: ds.timestamp)
    |> limit(1)
    |> DB.Repo.one()
  end

  @spec current_dataset_freshness(integer()) :: %{dataset_freshness: float | nil, details: map()}
  def current_dataset_freshness(dataset_id) do
    resources =
      DB.Dataset.base_query()
      |> DB.Resource.join_dataset_with_resource()
      |> where([dataset: d, resource: r], d.id == ^dataset_id and not r.is_community_resource)
      |> select([resource: r], r)
      |> DB.Repo.all()

    current_dataset_freshness_infos = resources |> Enum.map(&resource_freshness(&1))

    score =
      current_dataset_freshness_infos
      |> Enum.map(fn %{freshness: freshness} -> freshness end)
      |> Enum.reject(&is_nil(&1))
      |> average()

    %{dataset_freshness: score, details: %{resources: current_dataset_freshness_infos}}
  end

  defp average([]), do: nil
  defp average(e), do: Enum.sum(e) / Enum.count(e)

  @spec resource_freshness(map) ::
          %{
            :format => binary,
            :freshness => float | nil,
            :resource_id => integer,
            :raw_measure => any,
            :metadata_id => integer | nil,
            :metadata_inserted_at => binary | nil
          }
  def resource_freshness(%{format: "GTFS", id: resource_id}) do
    resource_id
    |> DB.MultiValidation.resource_latest_validation(Transport.Validators.GTFSTransport)
    |> case do
      %{
        metadata: %{
          metadata: %{"start_date" => start_date, "end_date" => end_date},
          id: metadata_id,
          inserted_at: inserted_at
        }
      }
      when not is_nil(start_date) and not is_nil(end_date) ->
        start_date = Date.from_iso8601!(start_date)
        end_date = Date.from_iso8601!(end_date)

        freshness = gtfs_freshness(start_date, end_date)

        %{
          freshness: freshness,
          raw_measure: %{start_date: start_date, end_date: end_date},
          metadata_id: metadata_id,
          metadata_inserted_at: inserted_at
        }

      _ ->
        %{
          freshness: nil,
          raw_measure: nil,
          metadata_id: nil,
          metadata_inserted_at: nil
        }
    end
    |> Map.merge(%{resource_id: resource_id, format: "GTFS"})
  end

  def resource_freshness(%{format: "gbfs", id: resource_id}) do
    freshness =
      resource_id
      |> resource_last_metadata_from_today()
      |> case do
        %{metadata: %{"feed_timestamp_delay" => feed_timestamp_delay}, id: metadata_id, inserted_at: inserted_at} ->
          %{
            freshness: gbfs_feed_freshness(feed_timestamp_delay),
            raw_measure: feed_timestamp_delay,
            metadata_id: metadata_id,
            metadata_inserted_at: inserted_at
          }

        _ ->
          %{
            freshness: nil,
            raw_measure: nil,
            metadata_id: nil,
            metadata_inserted_at: nil
          }
      end
      |> Map.merge(%{resource_id: resource_id, format: "gbfs"})

    freshness
  end

  def resource_freshness(%{format: "gtfs-rt", id: resource_id}) do
    freshness =
      resource_id
      |> resource_last_metadata_from_today()
      |> case do
        %{metadata: %{"feed_timestamp_delay" => feed_timestamp_delay}, id: metadata_id, inserted_at: inserted_at} ->
          %{
            freshness: gtfs_rt_feed_freshness(feed_timestamp_delay),
            raw_measure: feed_timestamp_delay,
            metadata_id: metadata_id,
            metadata_inserted_at: inserted_at
          }

        _ ->
          %{
            freshness: nil,
            raw_measure: nil,
            metadata_id: nil,
            metadata_inserted_at: nil
          }
      end
      |> Map.merge(%{resource_id: resource_id, format: "gtfs-rt"})

    freshness
  end

  def resource_freshness(%DB.Resource{format: format, id: resource_id}),
    do: %{
      format: format,
      resource_id: resource_id,
      freshness: nil,
      raw_measure: nil,
      metadata_id: nil,
      metadata_inserted_at: nil
    }

  @doc """
  the freshness of a GTFS resource, base on its validity dates

  iex> {today, tomorrow, yesterday} = {Date.utc_today(), Date.utc_today() |> Date.add(1), Date.utc_today() |> Date.add(-1)}
  iex> gtfs_freshness(tomorrow, tomorrow)
  nil
  iex> gtfs_freshness(yesterday, yesterday)
  0.0
  iex> gtfs_freshness(yesterday, tomorrow)
  1.0
  iex> gtfs_freshness(today, tomorrow)
  1.0
  iex> gtfs_freshness(yesterday, today)
  1.0
  """
  def gtfs_freshness(start_date, end_date) do
    today = Date.utc_today()

    case {Date.compare(start_date, today), Date.compare(end_date, today)} do
      # future GTFS are not scored
      {:gt, _} -> nil
      # outdated GTFS
      {_, :lt} -> 0.0
      # up-to-date GTFS
      _ -> 1.0
    end
  end

  @doc """
  5 minutes is the max delay allowed for GBFS
  https://github.com/MobilityData/gbfs/blob/master/gbfs.md#data-latency
  """
  def gbfs_max_timestamp_delay, do: 5 * 60

  @doc """
  gives a feed a freshness score, based on observed feed_timestamp_delay

  iex> gbfs_feed_freshness(0)
  1.0
  iex> gbfs_feed_freshness(1000)
  0.0
  """
  def gbfs_feed_freshness(feed_timestamp_delay) do
    if feed_timestamp_delay < gbfs_max_timestamp_delay(), do: 1.0, else: 0.0
  end

  @doc """
  we allow a 5 minutes delay for GTFS realtime feeds
  """
  def gtfs_rt_max_timestamp_delay, do: 5 * 60

  @doc """
  gives a feed a freshness score, based on observed feed_timestamp_delay

  iex> gtfs_rt_feed_freshness(0)
  1.0
  iex> gtfs_rt_feed_freshness(1000)
  0.0
  """
  def gtfs_rt_feed_freshness(feed_timestamp_delay) do
    if feed_timestamp_delay < gtfs_rt_max_timestamp_delay(), do: 1.0, else: 0.0
  end

  def resource_last_metadata_from_today(resource_id) do
    DB.ResourceMetadata.base_query()
    |> where(
      [metadata: m],
      m.resource_id == ^resource_id and fragment("date(?) = CURRENT_DATE", m.inserted_at)
    )
    |> distinct([metadata: m], m.resource_id)
    |> order_by([metadata: m], desc: m.inserted_at)
    |> DB.Repo.one()
  end
end
