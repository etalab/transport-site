defmodule DB.DatasetMonthlyMetric do
  @moduledoc """
  Monthly metrics related to datasets as given by the data.gouv.fr
  API.
  Example: https://metric-api.data.gouv.fr/api/datasets/data/?metric_month__sort=asc&dataset_id__exact=5b3cc551c751df4822526c1c
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Changeset

  typed_schema "dataset_monthly_metrics" do
    belongs_to(:dataset, DB.Dataset, foreign_key: :dataset_datagouv_id, references: :datagouv_id, type: :string)
    field(:year_month, :string)
    field(:metric_name, Ecto.Enum, values: [:views, :downloads])
    field(:count, :integer)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [:dataset_datagouv_id, :year_month, :metric_name, :count])
    |> validate_required([:dataset_datagouv_id, :year_month, :metric_name, :count])
    |> foreign_key_constraint(:dataset_datagouv_id)
    |> validate_format(:year_month, ~r/^2\d{3}-(0?[1-9]|1[012])$/)
    |> validate_number(:count, greater_than_or_equal_to: 0)
  end
end
