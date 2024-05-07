defmodule DB.Repo.Migrations.NotificationSubscriptionsMigratePlatformProducer do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE notification_subscription
    SET role = 'reuser'
    WHERE reason in ('datasets_switching_climate_resilience_bill', 'new_dataset')
      AND role = 'producer'
    """)
  end

  def down, do: IO.puts("No going back")
end
