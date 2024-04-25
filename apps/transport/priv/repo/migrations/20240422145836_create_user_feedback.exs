defmodule Transport.Repo.Migrations.CreateUserFeedback do
  use Ecto.Migration

  def change do
    create table(:user_feedback) do
      add(:rating, :string, null: false)
      add(:explanation, :text, null: false)
      add(:email, :binary)
      add(:feature, :string, null: false)

      timestamps(type: :utc_datetime_usec)
    end
  end
end
