defmodule DB.Repo.Migrations.AddDiscussionTimestamp do
  use Ecto.Migration

  def change do
    alter table("dataset") do
      add(:latest_data_gouv_comment_timestamp, :naive_datetime_usec)
    end
  end
end
