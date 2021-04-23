defmodule DB.GeomTest do
  @moduledoc """
  Tests on geom fields
  """
  use DB.DatabaseCase, cleanup: [:datasets]

  import Ecto.Query

  test "geom support for Region" do
    region = DB.Region |> last() |> DB.Repo.one!()
    assert region.geom == nil

    geom =
      "SRID=4326;POLYGON((55.58320119999998 -21.37236860026815,55.55105419999999 -21.37434010026793,55.53599659999998 -21.36315530026913))"
      |> Geo.WKT.decode!()

    assert geom.srid == 4326
    assert geom.properties == %{}

    assert geom.coordinates == [
             [
               {55.58320119999998, -21.37236860026815},
               {55.55105419999999, -21.37434010026793},
               {55.53599659999998, -21.36315530026913}
             ]
           ]

    region
    |> Ecto.Changeset.change(%{geom: geom})
    |> DB.Repo.update!()
  end
end
