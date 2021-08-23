defmodule DB.Repo.Migrations.CreateResourceQualityLogsTable do
  @moduledoc """
  A table for logging information about all the PAN resources "quality",
  ie availability, freshness, correctness, etc
  """
  use Ecto.Migration

  def change do
    create table(:logs_resource_quality) do
      add :resource_id,  references(:resource)
      add :log_date, :utc_datetime_usec
      add :resource_end_date, :date
      add :is_available, :boolean
      add :resource_format, :string
    end
  end
end
