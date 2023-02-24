defmodule DB.Repo.Migrations.AddNotificationSubscription do
  use Ecto.Migration

  def change do
    create table(:notification_subscription) do
      add :contact_id, references(:contact, on_delete: :delete_all), null: false
      add :dataset_id, references(:dataset, on_delete: :delete_all), null: true
      add :reason, :string, null: false
      add :source, :string, null: false

      timestamps([type: :utc_datetime_usec])
    end

    create index(:notification_subscription, [:contact_id])
    create index(:notification_subscription, [:dataset_id])
    create unique_index(
      :notification_subscription,
      [:contact_id, :dataset_id, :reason],
      name: :notification_subscription_contact_id_dataset_id_reason_index
    )
  end
end
