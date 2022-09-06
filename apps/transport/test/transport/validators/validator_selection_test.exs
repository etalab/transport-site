defmodule Transport.ValidatorsSelectionTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox

  doctest Transport.ValidatorsSelection, import: true
  alias Transport.ValidatorsSelection.Impl, as: ValidatorsSelection

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  describe "validators" do
    test "for a ResourceHistory with only a format" do
      resource_history = insert(:resource_history, payload: %{"format" => "GTFS"})

      assert ValidatorsSelection.validators(resource_history) == ValidatorsSelection.validators("GTFS")
      assert [Transport.Validators.GTFSTransport] == ValidatorsSelection.validators(resource_history)
    end

    test "for a ResourceHistory with a schema" do
      resource_history =
        insert(:resource_history, payload: %{"format" => "csv", "schema_name" => schema_name = "etalab/schema-zfe"})

      Transport.Shared.Schemas.Mock
      |> expect(:schemas_by_type, 2, fn type ->
        case type do
          "tableschema" -> %{}
          "jsonschema" -> %{schema_name => %{}}
        end
      end)

      assert [Transport.Validators.EXJSONSchema] == ValidatorsSelection.validators(resource_history)
    end

    test "for a Resource with a format" do
      resource = insert(:resource, format: "gbfs")

      assert [Transport.Validators.GBFSValidator] == ValidatorsSelection.validators(resource)
    end

    test "for a Resource with a schema" do
      resource = insert(:resource, format: "csv", schema_name: schema_name = "etalab/schema-zfe")

      Transport.Shared.Schemas.Mock
      |> expect(:schemas_by_type, 2, fn type ->
        case type do
          "tableschema" -> %{}
          "jsonschema" -> %{schema_name => %{}}
        end
      end)

      assert [Transport.Validators.EXJSONSchema] == ValidatorsSelection.validators(resource)
    end
  end
end
