defmodule DB.Repo.Migrations.AllowNeTExToGeoJSONConversion do
  use Ecto.Migration

  def up do
    drop(constraint("data_conversion", :allowed_from_formats))
    create(constraint("data_conversion", :allowed_from_formats, check: "convert_from IN ('GTFS', 'NeTEx')"))
  end

  def down do
    drop(constraint("data_conversion", :allowed_from_formats))
    create(constraint("data_conversion", :allowed_from_formats, check: "convert_from IN ('GTFS')"))
  end
end
