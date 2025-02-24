defmodule DB.DatasetScore do
  @moduledoc """
  Give a dataset a score for different topics
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query
  import Ecto.Changeset
  use Gettext, backend: TransportWeb.Gettext

  typed_schema "dataset_score" do
    belongs_to(:dataset, DB.Dataset)
    field(:topic, Ecto.Enum, values: [:freshness, :availability, :compliance])
    field(:score, :float)
    field(:timestamp, :utc_datetime_usec)
    field(:details, :map)
  end

  def changeset(%DB.DatasetScore{} = dataset_score, attrs) do
    dataset_score
    |> cast(attrs, [:dataset_id, :topic, :score, :timestamp, :details])
    |> validate_required([:dataset_id, :topic, :timestamp])
    |> validate_change(:score, &between_0_and_1_if_exists/2)
  end

  def between_0_and_1_if_exists(:score, score) when score >= 0.0 and score <= 1.0, do: []
  def between_0_and_1_if_exists(:score, nil), do: []
  def between_0_and_1_if_exists(:score, _score), do: [score: "must be between 0.0 and 1.0"]

  def base_query, do: from(ds in DB.DatasetScore, as: :dataset_score)

  @doc """
  Latest score for a given dataset and topic
  """
  @spec get_latest(DB.Dataset.t(), atom()) :: DB.DatasetScore.t() | nil
  def get_latest(%DB.Dataset{id: dataset_id}, topic) when is_atom(topic) do
    __MODULE__.base_query()
    |> where([dataset_score: ds], ds.dataset_id == ^dataset_id and ds.topic == ^topic)
    |> order_by([ds], desc: ds.timestamp)
    |> limit(1)
    |> DB.Repo.one()
  end

  @doc """
  Latest scores for a given dataset and a list of topics
  """
  @spec get_latest_scores(DB.Dataset.t(), [atom()]) :: %{required(atom()) => DB.DatasetScore.t()}
  def get_latest_scores(%DB.Dataset{id: dataset_id}, topics) when is_list(topics) do
    ids =
      __MODULE__.base_query()
      |> where([dataset_score: ds], ds.dataset_id == ^dataset_id and ds.topic in ^topics)
      |> select(
        [dataset_score: ds],
        ds.id |> first_value() |> over(partition_by: ds.topic, order_by: [desc: ds.timestamp])
      )
      |> distinct(true)

    __MODULE__.base_query()
    |> where([dataset_score: ds], ds.id in subquery(ids))
    |> DB.Repo.all()
    |> Enum.into(%{}, fn %__MODULE__{topic: topic} = ds -> {topic, ds} end)
  end

  def scores_over_last_days(%DB.Dataset{id: dataset_id}, nb_days) when is_integer(nb_days) and nb_days > 0 do
    dt_limit = %DateTime{DateTime.utc_now() | hour: 0, minute: 0, second: 0} |> DateTime.add(-nb_days, :day)

    # Find the latest point for each topic for this dataset, for each day
    ids =
      __MODULE__.base_query()
      |> where([dataset_score: ds], ds.dataset_id == ^dataset_id and ds.timestamp >= ^dt_limit)
      |> select(
        [dataset_score: ds],
        ds.id
        |> first_value()
        |> over(partition_by: [ds.topic, fragment("?::date", ds.timestamp)], order_by: [desc: ds.timestamp])
      )
      |> distinct(true)

    __MODULE__.base_query()
    |> where([dataset_score: ds], ds.id in subquery(ids))
    |> order_by([dataset_score: ds], asc: ds.timestamp, asc: ds.topic)
    |> DB.Repo.all()
  end

  @doc """
  iex> score_for_humans(%DB.DatasetScore{score: nil})
  nil
  iex> score_for_humans(%DB.DatasetScore{score: 0.123})
  12
  """
  @spec score_for_humans(__MODULE__.t()) :: nil | integer()
  def score_for_humans(%__MODULE__{score: nil}), do: nil
  def score_for_humans(%__MODULE__{score: score}), do: Kernel.round(score * 100)

  @doc """
  iex> DB.DatasetScore |> Ecto.Enum.values(:topic) |> Enum.each(&topic_for_humans/1)
  :ok
  """
  @spec topic_for_humans(atom() | binary()) :: binary()
  def topic_for_humans(topic) when is_atom(topic), do: topic |> to_string() |> topic_for_humans()

  def topic_for_humans(topic) when is_binary(topic) do
    Map.fetch!(
      %{
        "freshness" => dgettext("db-dataset-score", "freshness"),
        "availability" => dgettext("db-dataset-score", "availability"),
        "compliance" => dgettext("db-dataset-score", "compliance")
      },
      topic
    )
  end
end
