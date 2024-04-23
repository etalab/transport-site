defmodule Unlock.DynamicIRVESchemaTest do
  use ExUnit.Case, async: false

  test "enumerates current fields" do
    field_names =
      Unlock.DynamicIRVESchema.schema_content()
      |> get_in(["fields"])
      |> Enum.map(& &1["name"])

    assert field_names == [
             "id_pdc_itinerance",
             "etat_pdc",
             "occupation_pdc",
             "horodatage",
             "etat_prise_type_2",
             "etat_prise_type_combo_ccs",
             "etat_prise_type_chademo",
             "etat_prise_type_ef"
           ]
  end
end
