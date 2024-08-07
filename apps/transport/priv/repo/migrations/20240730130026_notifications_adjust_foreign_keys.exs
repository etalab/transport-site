defmodule DB.Repo.Migrations.NotificationsAdjustForeignKeys do
  use Ecto.Migration

  def change do
    # Review foreign key settings previously set in
    # 20240604121342_notifications_add_columns.exs
    alter table(:notifications) do
      modify(:notification_subscription_id, references(:notification_subscription, on_delete: :nilify_all),
        from: references(:notification_subscription, on_delete: :nothing)
      )

      modify(:contact_id, references(:contact, on_delete: :nilify_all), from: references(:contact, on_delete: :nothing))
    end
  end
end
