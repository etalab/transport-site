defmodule DB.Repo.Migrations.CreateConversionTable do
  use Ecto.Migration

  def change do
    create table("data_conversion") do
      # FIX ME
      # We should be able to add a foreign key to resource.datagouv_id
      # but for now datagouv_id is not unique
      # See https://github.com/etalab/transport-site/issues/1930
      add :convert_from, :string, null: false
      add :convert_to, :string, null: false
      add :resource_history_uuid, :uuid, null: false
      add :payload, :jsonb, null: false

      timestamps([type: :utc_datetime_usec])
    end

    create unique_index("data_conversion", [:convert_from, :convert_to, :resource_history_uuid])
    create constraint("data_conversion", :allowed_from_formats, check: "convert_from IN ('GTFS')")
    create constraint("data_conversion", :allowed_to_formats, check: "convert_to IN ('GeoJSON')")
  end
end
