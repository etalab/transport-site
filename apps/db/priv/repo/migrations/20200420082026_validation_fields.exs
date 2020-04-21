defmodule DB.Repo.Migrations.ValidationFields do
  use Ecto.Migration

  def up do
    alter table(:validations) do
      add(:max_error, :string)
    end
    alter table(:resource) do
      add(:start_date, :date)
      add(:end_date, :date)
    end
    create(index(:validations, [:max_error]))
    create(index(:resource, [:start_date, :end_date]))

    dt = Date.utc_today() |> Date.to_iso8601()

    execute("""
    UPDATE validations v SET
    max_error = (
      SELECT severity FROM (
        SELECT distinct(json_data.value#>>'{0,severity}') as severity
        FROM validations
        JOIN resource ON resource.id = validations.resource_id,
        json_each(validations.details) json_data
        WHERE
        (validations.id = v.id)
        -- we only consider valid resources
        AND resource.metadata->>'end_date' IS NOT NULL
        AND resource.metadata->>'end_date' > '#{dt}'
      ) AS severities
      ORDER BY (
        CASE severity::text
          WHEN 'Fatal' THEN 1
          WHEN 'Error' THEN 2
          WHEN 'Warning' THEN 3
          WHEN 'Information' THEN 4
          WHEN 'Irrelevant' THEN 5
        END
      ) ASC
      LIMIT 1
    );
    """)


    execute("""
    UPDATE resource SET
    start_date = TO_DATE(metadata->>'start_date', 'YYYY-MM-DD'),
    end_date = TO_DATE(metadata->>'end_date', 'YYYY-MM-DD');
    """)
  end

  def down do
    alter table(:validations) do
      remove(:start_date)
      remove(:end_date)
      remove(:max_error)
    end
  end
end
