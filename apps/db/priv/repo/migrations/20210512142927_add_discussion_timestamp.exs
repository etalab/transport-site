defmodule DB.Repo.Migrations.AddDiscussionTimestamp do
  use Ecto.Migration

  def change do
    alter table("dataset") do
      add(:latest_data_gouv_comment_timestamp, :utc_datetime)
    end
  end
end
