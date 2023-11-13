defmodule DB.Repo.Migrations.NotificationSubscriptionAddRole do
  use Ecto.Migration

  def up do
    alter table(:notification_subscription) do
      add(:role, :string, null: true)
    end

    execute("update notification_subscription set role = 'producer'")

    alter table(:notification_subscription) do
      modify(:role, :varchar, null: false, from: :varchar)
    end
  end

  def down do
    alter table(:notification_subscription) do
      remove(:role)
    end
  end
end
