defmodule DB.Repo.Migrations.NotificationSubscriptionRenameSwitchingLicencesReason do
  use Ecto.Migration

  def change do
    up_migration = "UPDATE notification_subscription SET reason = 'datasets_switching_climate_resilience_bill' WHERE reason = 'datasets_switching_licences'"
    down_migration = "UPDATE notification_subscription SET reason = 'datasets_switching_licences' WHERE reason = 'datasets_switching_climate_resilience_bill'"
    execute up_migration, down_migration
  end
end
