defmodule DB.Repo.Migrations.DataConversionAddColumns do
  use Ecto.Migration

  def up do
    alter table("data_conversion") do
      add(:status, :string)
      add(:converter, :string)
      add(:converter_version, :string)
    end

    drop(unique_index("data_conversion", [:convert_from, :convert_to, :resource_history_uuid]))

    execute("update data_conversion set status = 'success'")
    # https://github.com/etalab/transport-tools/blob/278f66679537981176f414de8027a86b1b0808ba/Dockerfile#L38
    execute(
      "update data_conversion set converter = 'hove/transit_model', converter_version = '0.55.0' where convert_to = 'NeTEx' and convert_from = 'GTFS'"
    )

    # https://github.com/etalab/transport-tools/blob/278f66679537981176f414de8027a86b1b0808ba/Dockerfile#L8
    execute(
      "update data_conversion set converter = 'rust-transit/gtfs-to-geojson', converter_version = '0.3.1' where convert_to = 'GeoJSON' and convert_from = 'GTFS'"
    )

    alter table("data_conversion") do
      modify(:status, :varchar, null: false, from: {:string, null: true})
      modify(:converter, :varchar, null: false, from: {:string, null: true})
      modify(:converter_version, :varchar, null: false, from: {:string, null: true})
    end

    create(index("data_conversion", [:convert_from, :convert_to, :converter]))
    create(unique_index("data_conversion", [:convert_from, :convert_to, :converter, :resource_history_uuid]))
  end

  def down do
    alter table("data_conversion") do
      drop(:status)
      drop(:converter)
      drop(:converter_version)
    end

    create(unique_index("data_conversion", [:convert_from, :convert_to, :resource_history_uuid]))
  end
end
