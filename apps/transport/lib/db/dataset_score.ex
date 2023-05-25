defmodule DB.DatasetScore do
  @moduledoc """
  Give a dataset a score for different topics
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query

  typed_schema "dataset_score" do
    belongs_to(:dataset, DB.Dataset)
    field(:topic, :string)
    field(:score, :float)
    field(:timestamp, :utc_datetime_usec)
  end

  def base_query(), do: from(ds in DB.DatasetScore, as: :dataset_score)
end
