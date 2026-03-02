defmodule DB.DatasetMonthlyMetric do
  @moduledoc """
  Monthly metrics related to datasets as given by the data.gouv.fr
  API.

  - `:downloads`: counts the number of `GET` requests for all the dataset resources,
  as seen by the data.gouv.fr's infrastructure. It only makes sense for resources
  hosted on data.gouv.fr, not for resources hosted on third party servers.
  - `:views`: counts the number of `GET` requests on the dataset web page.

  Example: https://metric-api.data.gouv.fr/api/datasets/data/?metric_month__sort=asc&dataset_id__exact=5b3cc551c751df4822526c1c
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Changeset
  import Ecto.Query

  typed_schema "dataset_monthly_metrics" do
    # Foreign key constraint is not enforced on the dataset table
    # See: https://github.com/etalab/transport-site/pull/3663/files#r1429890393
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
    |> validate_format(:year_month, ~r/\A2\d{3}-(0[1-9]|1[012])\z/)
    |> validate_number(:count, greater_than_or_equal_to: 0)
  end

  @spec downloads_for_year([DB.Dataset.t()], non_neg_integer()) :: %{binary() => integer()}
  def downloads_for_year(datasets, year) do
    datagouv_ids = Enum.map(datasets, fn %DB.Dataset{datagouv_id: datagouv_id} -> datagouv_id end)
    year_months = year_months(year)

    DB.DatasetMonthlyMetric
    |> where(
      [dm],
      dm.metric_name == :downloads and dm.dataset_datagouv_id in ^datagouv_ids and dm.year_month in ^year_months
    )
    |> group_by([dm], dm.dataset_datagouv_id)
    |> select([dm], {dm.dataset_datagouv_id, sum(dm.count)})
    |> DB.Repo.all()
    |> Map.new()
  end

  @doc """
  `YYYY-MM` possibilities for a specific year

  iex> year_months(2023)
  ["2023-01", "2023-02", "2023-03", "2023-04", "2023-05", "2023-06", "2023-07", "2023-08", "2023-09", "2023-10", "2023-11", "2023-12"]
  """
  @spec year_months(integer()) :: [binary()]
  def year_months(year) do
    Enum.map(1..12, &("#{year}-" <> String.pad_leading(to_string(&1), 2, "0")))
  end
end
