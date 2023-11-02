defmodule DB.Repo.Migrations.NotificationSubscriptionRenameLicenceOuverteReason do
  use Ecto.Migration

  def change do
    up_migration =
      "UPDATE notification_subscription SET reason = 'datasets_switching_licences' WHERE reason = 'dataset_now_licence_ouverte'"

    down_migration =
      "UPDATE notification_subscription SET reason = 'dataset_now_licence_ouverte' WHERE reason = 'datasets_switching_licences'"

    execute(up_migration, down_migration)
  end
end
