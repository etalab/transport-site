defmodule DB.DatasetScore do
  @moduledoc """
  Give a dataset a score for different topics
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query
  import Ecto.Changeset

  typed_schema "dataset_score" do
    belongs_to(:dataset, DB.Dataset)
    field(:topic, :string)
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

  @spec get_latest(DB.Dataset.t(), any) :: DB.DatasetScore.t() | nil
  @doc """
  Latest score for a given dataset and topic
  """
  def get_latest(%DB.Dataset{id: dataset_id}, topic) do
    __MODULE__.base_query()
    |> where([dataset_score: ds], ds.dataset_id == ^dataset_id and ds.topic == ^topic)
    |> order_by([ds], desc: ds.timestamp)
    |> limit(1)
    |> DB.Repo.one()
  end
end
