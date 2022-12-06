defmodule DB.Repo.Migrations.OnDeleteNilify do
  use Ecto.Migration

  def change do
    alter table(:dataset_history) do
      modify(:dataset_id, references(:dataset, on_delete: :nilify_all),
        from: references(:dataset, on_delete: :nothing)
      )
    end

    alter table(:dataset_history_resources) do
      modify(:resource_id, references(:resource, on_delete: :nilify_all),
        from: references(:resource, on_delete: :nothing)
      )

      modify(:resource_history_id, references(:resource_history, on_delete: :nilify_all),
        from: references(:resource_history, on_delete: :nothing)
      )

      modify(:resource_metadata_id, references(:resource_metadata, on_delete: :nilify_all),
        from: references(:resource_metadata, on_delete: :nothing)
      )

      modify(:validation_id, references(:multi_validation, on_delete: :nilify_all),
        from: references(:multi_validation, on_delete: :nothing)
      )
    end
  end
end
