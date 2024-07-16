defmodule Unlock.DynamicIRVESchemaTest do
  use ExUnit.Case, async: false

  test "enumerates current fields" do
    assert Unlock.DynamicIRVESchema.build_schema_fields_list() == [
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
