defmodule DB.IRVEValidPDCTest do
  use ExUnit.Case, async: true

  @moduledoc """
  This module is mostly empty as the behaviours of DB.IRVEValidPDC and DB.IRVEValidFile
  are already tested through Transport.IRVE.DatabaseImporter.
  """

  test "all IRVE static schema fields are present" do
    official_schema_fields = Transport.IRVE.StaticIRVESchema.field_names_list()
    ecto_schema_fields = DB.IRVEValidPDC.__schema__(:fields) |> Enum.map(&Atom.to_string/1)

    assert official_schema_fields -- ["coordonneesXY"] ==
             ecto_schema_fields --
               ["id", "irve_valid_file_id", "inserted_at", "updated_at", "longitude", "latitude"]
  end
end
