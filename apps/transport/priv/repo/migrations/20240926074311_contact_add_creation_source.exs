defmodule DB.Repo.Migrations.ContactAddCreationSource do
  use Ecto.Migration

  def change do
    alter table(:contact) do
      add(:creation_source, :string)
    end

    execute(
      """
      UPDATE contact
      SET creation_source = 'automation:import_contact_point'
      WHERE id in (
        SELECT distinct contact_id
        FROM notification_subscription
        WHERE source = 'automation:import_contact_point'
      )
      """,
      ""
    )

    execute(
      """
      UPDATE contact
      SET creation_source = 'admin'
      WHERE creation_source IS NULL
        AND (last_login_at IS NULL OR inserted_at::date = '2023-03-02')
      """,
      ""
    )

    execute(
      """
      UPDATE contact
      SET creation_source = 'datagouv_oauth_login'
      WHERE creation_source IS NULL
      """,
      ""
    )

    # Make sure the column is not null
    execute("ALTER TABLE contact ALTER COLUMN creation_source SET NOT NULL", "")
  end
end
