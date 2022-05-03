defmodule DB.Repo.Migrations.AllowNetexConversion do
  use Ecto.Migration

  def up do
    drop constraint("data_conversion", :allowed_to_formats)
    create constraint("data_conversion", :allowed_to_formats, check: "convert_to IN ('GeoJSON', 'NeTEx')")
  end

  def down do
    drop constraint("data_conversion", :allowed_to_formats)
    create constraint("data_conversion", :allowed_to_formats, check: "convert_to IN ('GeoJSON')")
  end
end
