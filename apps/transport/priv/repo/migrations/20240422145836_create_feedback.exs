defmodule Transport.Repo.Migrations.CreateFeedback do
  use Ecto.Migration

  def change do
    create table(:feedback) do
      add(:rating, :string, null: false)
      add(:explanation, :string, null: false)
      add(:email, :binary)
      add(:feature, :string, null: false)

      timestamps(type: :utc_datetime_usec)
    end
  end
end
