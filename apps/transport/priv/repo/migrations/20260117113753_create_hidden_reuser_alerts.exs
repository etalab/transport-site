defmodule DB.Repo.Migrations.CreateHiddenReuserAlerts do
  use Ecto.Migration

  def change do
    create table(:hidden_reuser_alerts) do
      add(:contact_id, references(:contact, on_delete: :delete_all), null: false)
      add(:dataset_id, references(:dataset, on_delete: :delete_all), null: false)
      add(:check_type, :string, null: false)
      add(:resource_id, :integer)
      add(:discussion_id, :string)
      add(:hidden_until, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:hidden_reuser_alerts, [:contact_id]))
    create(index(:hidden_reuser_alerts, [:dataset_id]))

    create(
      unique_index(
        :hidden_reuser_alerts,
        [:contact_id, :dataset_id, :check_type, :resource_id, :discussion_id],
        name: :hidden_reuser_alerts_unique_index
      )
    )
  end
end
