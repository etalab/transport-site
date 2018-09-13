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
    assert {:ok, dataset}  = DataValidation.create_dataset(attrs)
    assert {:ok, ^dataset} = DataValidation.find_dataset(attrs)
    assert {:ok, dataset}  = DataValidation.validate_dataset(dataset)
    assert {:ok, ^dataset} = DataValidation.find_dataset(attrs)
    assert %{"validations" => [%{"issue_type" => "UnusedStop"} | _], "metadata" => %{}} = dataset.validations
  end
end
