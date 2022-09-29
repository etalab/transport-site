defmodule DB.Repo.Migrations.FixGeometries do
  use Ecto.Migration

  def change do
    # See https://github.com/etalab/contours-administratifs/issues/27
    for table <- ~w(commune region departement) do
      execute "update #{table} set geom = ST_MakeValid(geom) where not st_isvalid(geom);"
    end
  end
end
