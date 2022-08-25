defmodule Transport.Jobs.Backfill.ResourceHistorySchemaDetailsTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.Backfill.ResourceHistorySchemaDetails
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "it updates the payload column" do
    schema_name = "etalab/foo"
    resource = insert(:resource, schema_name: schema_name)
    resource_with_schema_version = insert(:resource, schema_name: schema_name, schema_version: schema_version = "0.1.2")
    resource_history = insert(:resource_history, resource_id: resource.id)

    resource_history_with_schema =
      insert(:resource_history,
        resource_id: resource.id,
        payload: existing_payload = %{"schema_name" => schema_name, "foo" => "bar"}
      )

    resource_history_without_version = insert(:resource_history, resource_id: resource_with_schema_version.id)

    assert :ok == perform_job(ResourceHistorySchemaDetails, %{})

    assert %DB.ResourceHistory{payload: %{"schema_name" => ^schema_name, "schema_version" => nil}} =
             DB.Repo.reload!(resource_history)

    assert %DB.ResourceHistory{payload: %{"schema_name" => ^schema_name, "schema_version" => ^schema_version}} =
             DB.Repo.reload!(resource_history_without_version)

    assert %DB.ResourceHistory{payload: ^existing_payload} = DB.Repo.reload!(resource_history_with_schema)
  end
end
