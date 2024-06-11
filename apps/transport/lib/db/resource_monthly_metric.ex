defmodule DB.ResourceMonthlyMetric do
  @moduledoc """
  Monthly metrics related to resources as given by the data.gouv.fr
  API.
  Example: https://metric-api.data.gouv.fr/api/resources/data/?metric_month__sort=desc&resource_id__exact=e0dbd217-15cd-4e28-9459-211a27511a34&page_size=50
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Changeset

  typed_schema "resource_monthly_metrics" do
    belongs_to(:resource, DB.Resource, foreign_key: :resource_datagouv_id, references: :datagouv_id, type: :string)
    belongs_to(:dataset, DB.Dataset, foreign_key: :dataset_datagouv_id, references: :datagouv_id, type: :string)
    field(:year_month, :string)
    field(:metric_name, Ecto.Enum, values: [:downloads])
    field(:count, :integer)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [:resource_datagouv_id, :dataset_datagouv_id, :year_month, :metric_name, :count])
    |> validate_required([:resource_datagouv_id, :year_month, :metric_name, :count])
    |> validate_format(:year_month, ~r/\A2\d{3}-(0[1-9]|1[012])\z/)
    |> validate_number(:count, greater_than_or_equal_to: 0)
  end
end
