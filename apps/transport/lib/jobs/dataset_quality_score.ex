defmodule Transport.Jobs.DatasetQualityScoreDispatcher do
  @moduledoc """
  Computes quality scores for a dataset
  """
  use Oban.Worker, unique: [period: 60 * 60 * 20], max_attempts: 1
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    DB.Dataset.base_query()
    |> select([dataset: d], d.id)
    |> DB.Repo.all()
    |> Enum.map(&(%{dataset_id: &1} |> Transport.Jobs.DatasetQualityScore.new()))
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
    Transport.Jobs.DatasetFreshnessScore.save_freshness_score(dataset_id)
    Transport.Jobs.DatasetAvailabilityScore.save_availability_score(dataset_id)
    :ok
  end

  @doc """
  Build the details map to explain the score computation

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

  @doc """
  Exponential smoothing. See https://en.wikipedia.org/wiki/Exponential_smoothing

  iex> exp_smoothing(0.5, 1)
  0.55
  """
  @spec exp_smoothing(float, float) :: float
  def exp_smoothing(previous_score, today_score) do
    alpha = 0.9
    alpha * previous_score + (1.0 - alpha) * today_score
  end

  @spec last_dataset_score(integer(), atom()) :: DB.DatasetScore.t() | nil
  def last_dataset_score(dataset_id, topic) do
    # if a previous score exists but is too old, it is not used
    max_last_score_age_days = 7

    DB.DatasetScore.base_query()
    |> where(
      [ds],
      ds.dataset_id == ^dataset_id and ds.topic == ^topic and not is_nil(ds.score) and
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

  @doc """
  Computes the average of a list of values.

  iex> average([])
  nil
  iex> average([1, 3])
  2.0
  """
  def average([]), do: nil
  def average(e), do: Enum.sum(e) / Enum.count(e)

  @spec dataset_resources(integer()) :: [DB.Resource.t()]
  def dataset_resources(dataset_id) do
    DB.Dataset.base_query()
    |> DB.Resource.join_dataset_with_resource()
    |> where([dataset: d, resource: r], d.id == ^dataset_id and not r.is_community_resource)
    |> select([resource: r], r)
    |> DB.Repo.all()
  end

  @spec save_dataset_score(integer(), (integer() -> %{score: nil | float(), details: map()}), atom()) ::
          DB.DatasetScore.t() | nil
  def save_dataset_score(dataset_id, compute_fn, topic) do
    %{score: score, details: details} = dataset_score(dataset_id, compute_fn, topic)

    %DB.DatasetScore{}
    |> DB.DatasetScore.changeset(%{
      dataset_id: dataset_id,
      topic: topic,
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
          extra: %{dataset_id: dataset_id, topic: to_string(topic), error_reason: inspect(c)}
        )

        nil
    end
  end

  @spec dataset_score(integer(), (integer() -> %{score: nil | float(), details: map()}), atom()) :: %{
          score: float | nil,
          details: map()
        }
  def dataset_score(dataset_id, compute_fn, topic) do
    %{score: today_score, details: details} = compute_fn.(dataset_id)

    computed_score =
      case last_score = last_dataset_score(dataset_id, topic) do
        %{score: previous_score} when is_float(previous_score) ->
          exp_smoothing(previous_score, today_score)

        _ ->
          today_score
      end

    %{score: computed_score, details: build_details(details, last_score)}
  end
end

defmodule Transport.Jobs.DatasetAvailabilityScore do
  @moduledoc """
  Methods specific to the availability component of a dataset score.
  """
  import Ecto.Query
  import Transport.Jobs.DatasetQualityScore

  def save_availability_score(dataset_id) do
    save_dataset_score(dataset_id, &current_dataset_availability/1, :availability)
  end

  @spec current_dataset_availability(integer()) :: %{score: float | nil, details: map()}
  def current_dataset_availability(dataset_id) do
    resources = dataset_resources(dataset_id)
    current_dataset_infos = resources |> Enum.map(&resource_availability(&1))
    scores = current_dataset_infos |> Enum.map(fn %{availability: availability} -> availability end)

    score =
      if Enum.count(scores) > 0 and Enum.min(scores) == 0 do
        0
      else
        average(scores)
      end

    %{score: score, details: %{resources: current_dataset_infos}}
  end

  @spec resource_availability(DB.Resource.t()) :: %{
          :availability => float,
          :resource_id => integer,
          :raw_measure => any
        }
  def resource_availability(%DB.Resource{id: resource_id} = resource) do
    if resource_id in resource_ids_with_unavailabilities() do
      percentage = DB.ResourceUnavailability.availability_over_last_days(resource, 1)
      %{availability: availability_percentage_to_score(percentage), resource_id: resource_id, raw_measure: percentage}
    else
      %{availability: 1.0, resource_id: resource_id, raw_measure: nil}
    end
  end

  @doc """
  iex> availability_percentage_to_score(99.5)
  1.0
  iex> availability_percentage_to_score(98)
  0.75
  iex> availability_percentage_to_score(96)
  0.5
  iex> availability_percentage_to_score(94.9)
  0.0
  """
  @spec availability_percentage_to_score(float()) :: float()
  def availability_percentage_to_score(percentage) when percentage >= 0 and percentage <= 100 do
    cond do
      percentage >= 99.5 -> 1.0
      percentage >= 97.5 -> 0.75
      percentage >= 95 -> 0.5
      true -> 0.0
    end
  end

  def resource_ids_with_unavailabilities do
    Transport.Cache.API.fetch(
      to_string(__MODULE__) <> ":unavailabilities_resource_ids",
      fn ->
        dt_limit = DateTime.utc_now() |> DateTime.add(-1, :day)

        DB.ResourceUnavailability
        |> where([r], is_nil(r.end) or r.end >= ^dt_limit)
        |> select([r], r.resource_id)
        |> distinct(true)
        |> DB.Repo.all()
      end,
      :timer.seconds(60)
    )
  end
end

defmodule Transport.Jobs.DatasetFreshnessScore do
  @moduledoc """
  Methods specific to the freshness component of a dataset score.
  """
  import Ecto.Query
  import Transport.Jobs.DatasetQualityScore

  @doc """
  Dataset "freshness" is the answer to the question: "When the data was downloaded, was it up-to-date?"

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
  def save_freshness_score(dataset_id) do
    save_dataset_score(dataset_id, &current_dataset_freshness/1, :freshness)
  end

  @spec current_dataset_freshness(integer()) :: %{score: float | nil, details: map()}
  def current_dataset_freshness(dataset_id) do
    resources = dataset_resources(dataset_id)
    current_dataset_infos = resources |> Enum.map(&resource_freshness(&1))

    score =
      current_dataset_infos
      |> Enum.map(fn %{freshness: freshness} -> freshness end)
      |> Enum.reject(&is_nil(&1))
      |> average()

    %{score: score, details: %{resources: current_dataset_infos}}
  end

  @spec resource_freshness(DB.Resource.t()) ::
          %{
            :format => binary,
            :freshness => float | nil,
            :resource_id => integer,
            :raw_measure => any,
            :metadata_id => integer | nil,
            :metadata_inserted_at => binary | nil
          }
  def resource_freshness(%DB.Resource{format: "GTFS" = format, id: resource_id}) do
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
    |> Map.merge(%{resource_id: resource_id, format: format})
  end

  def resource_freshness(%DB.Resource{format: "gbfs" = format, id: resource_id}) do
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
    |> Map.merge(%{resource_id: resource_id, format: format})
  end

  def resource_freshness(%DB.Resource{format: "gtfs-rt" = format, id: resource_id}) do
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
    |> Map.merge(%{resource_id: resource_id, format: format})
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
  The freshness of a GTFS resource, base on its validity dates

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
  Gives a feed a freshness score, based on observed feed_timestamp_delay

  iex> gbfs_feed_freshness(0)
  1.0
  iex> gbfs_feed_freshness(1000)
  0.0
  """
  def gbfs_feed_freshness(feed_timestamp_delay) do
    if feed_timestamp_delay < gbfs_max_timestamp_delay(), do: 1.0, else: 0.0
  end

  @doc """
  We allow a 5 minutes delay for GTFS realtime feeds
  """
  def gtfs_rt_max_timestamp_delay, do: 5 * 60

  @doc """
  Gives a feed a freshness score, based on observed feed_timestamp_delay

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
