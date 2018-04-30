defmodule Transport.DataValidationTest do
  use ExUnit.Case, async: true
  use TransportWeb.DatabaseCase, cleanup: ["datasets"]
  alias Transport.DataValidation

  @moduletag :integration
  doctest DataValidation

  setup do
    {:ok,
     download_url:
       "https://applications002.brest-metropole.fr/VIPDU72/GPB/Lot_BrestMetropole_Bibus.zip"}
  end

  test "validates a dataset", attrs do
    {:ok, dataset} = DataValidation.create_dataset(attrs)
    {:ok, ^dataset} = DataValidation.find_dataset(attrs)
    {:ok, [%{issue_type: "UnusedStop"} | _]} = DataValidation.validate_dataset(dataset)
    {:ok, %{validations: [%{issue_type: "UnusedStop"} | _]}} = DataValidation.find_dataset(attrs)
  end
end
