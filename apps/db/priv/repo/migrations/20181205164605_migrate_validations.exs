defmodule DB.Repo.Migrations.MigrateValidations do
  use Ecto.Migration
  alias Ecto.Adapters.SQL
  alias DB.{Repo, Resource}

  defp convert([id, validations, validation_date, download_url]) do
    %{
      dataset_id: id,
      validations:  validations,
      validation_date: validation_date,
      url: download_url,
      is_active: true
    }
  end

  def change do
    #sql = "SELECT id, validations, validation_date, download_url FROM dataset"
    #{:ok, %{rows: rows}} = SQL.query(Repo, sql)
    #resources = Enum.map(rows, &convert/1)
    #
    #Repo.insert_all(Resource, resources)

    alter table(:dataset) do
      remove :validations
      remove :validation_date
      remove :download_url
    end
  end
end
