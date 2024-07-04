defmodule DB.Repo.Migrations.NotificationsAddColumns do
  use Ecto.Migration

  def change do
    alter table(:notifications) do
      add(:notification_subscription_id, references(:notification_subscription, on_delete: :nothing))
      add(:contact_id, references(:contact, on_delete: :nothing))
      add(:role, :string)
      add(:payload, :jsonb)
    end

    # Existing rows have been sent ~95% of the time to producers.
    # The rest of the rows will be fixed in production with some queries
    # (administrators dogfooding the upcoming reuser space).
    execute("UPDATE notifications SET role = 'producer'", "")

    execute("ALTER TABLE notifications ALTER COLUMN role SET NOT NULL", "")
  end
end
