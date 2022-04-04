defmodule DB.GeomTest do
  @moduledoc """
  Tests on geom fields
  """
  use DB.DatabaseCase, cleanup: [:datasets]

  import Ecto.Query

  # NOTE: we could add DB.DatasetGeographicView here, but we lack an example record
  @modules [DB.Region, DB.AOM, DB.Commune]

  Enum.each(@modules, fn tested_module ->
    test "geom support for #{tested_module |> inspect}" do
      # load the test record
      instance = unquote(tested_module) |> last() |> DB.Repo.one!()
      assert instance.geom == nil

      # create a geometry from text (unrelated to Ecto)
      geom =
        "SRID=4326;POLYGON((55.58320119999998 -21.37236860026815,55.55105419999999 -21.37434010026793,55.53599659999998 -21.36315530026913,55.58320119999998 -21.37236860026815))"
        |> Geo.WKT.decode!()

      assert geom.srid == 4326
      assert geom.properties == %{}

      assert geom.coordinates == [
               [
                 {55.58320119999998, -21.37236860026815},
                 {55.55105419999999, -21.37434010026793},
                 {55.53599659999998, -21.36315530026913},
                 {55.58320119999998, -21.37236860026815}
               ]
             ]

      # update the record (geo_postgis should serialize as needed)
      instance
      |> Ecto.Changeset.change(%{geom: geom})
      |> DB.Repo.update!()

      # reload after save, just unserialize as needed, and leave unchanged
      instance = DB.Repo.get!(unquote(tested_module), instance.id)
      assert instance.geom == geom
    end
  end)
end
