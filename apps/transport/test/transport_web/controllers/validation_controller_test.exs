defmodule TransportWeb.SeoMetadataTest do
  use TransportWeb.ConnCase, async: true
  use Oban.Testing, repo: DB.Repo
  import Ecto.Query
  import Mox
  alias Transport.Test.S3TestUtils

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "GET /validation ", %{conn: conn} do
    Transport.Shared.Schemas.Mock |> expect(:transport_schemas, fn -> %{} end)
    conn |> get("/validation") |> html_response(200)
  end

  describe "POST validate" do
    test "with a GTFS", %{conn: conn} do
      Transport.Shared.Schemas.Mock |> expect(:transport_schemas, fn -> %{} end)
      S3TestUtils.s3_mocks_upload_file("")
      assert 0 == count_validations()

      conn =
        conn
        |> post("/validation", %{
          "upload" => %{"file" => %Plug.Upload{path: "#{__DIR__}/../../fixture/files/gtfs.zip"}, "type" => "gtfs"}
        })

      assert 1 == count_validations()

      assert %{
               on_the_fly_validation_metadata: %{
                 "filename" => filename,
                 "permanent_url" => permanent_url,
                 "state" => "waiting",
                 "type" => "gtfs"
               },
               id: validation_id
             } = DB.Repo.one!(DB.Validation)

      assert [
               %Oban.Job{
                 args: %{
                   "id" => ^validation_id,
                   "state" => "waiting",
                   "filename" => ^filename,
                   "permanent_url" => ^permanent_url,
                   "type" => "gtfs"
                 }
               }
             ] = all_enqueued(worker: Transport.Jobs.OnDemandValidationJob)

      assert permanent_url == Transport.S3.permanent_url(:on_demand_validation, filename)
      assert redirected_to(conn, 302) =~ "/validation/#{validation_id}"
    end

    test "with a schema", %{conn: conn} do
      schema_name = "etalab/foo"

      Transport.Shared.Schemas.Mock
      |> expect(:transport_schemas, 2, fn -> %{schema_name => %{"type" => "tableschema", "title" => "foo"}} end)

      S3TestUtils.s3_mocks_upload_file("")
      assert 0 == count_validations()

      conn =
        conn
        |> post("/validation", %{
          "upload" => %{"file" => %Plug.Upload{path: "#{__DIR__}/../../fixture/files/gtfs.zip"}, "type" => schema_name}
        })

      assert 1 == count_validations()

      assert %{
               on_the_fly_validation_metadata: %{
                 "filename" => filename,
                 "permanent_url" => permanent_url,
                 "state" => "waiting",
                 "type" => "tableschema",
                 "schema_name" => ^schema_name
               },
               id: validation_id
             } = DB.Repo.one!(DB.Validation)

      assert permanent_url == Transport.S3.permanent_url(:on_demand_validation, filename)

      assert [
               %Oban.Job{
                 args: %{
                   "id" => ^validation_id,
                   "state" => "waiting",
                   "filename" => ^filename,
                   "permanent_url" => ^permanent_url,
                   "type" => "tableschema",
                   "schema_name" => ^schema_name
                 }
               }
             ] = all_enqueued(worker: Transport.Jobs.OnDemandValidationJob)

      assert redirected_to(conn, 302) =~ "/validation/#{validation_id}"
    end
  end

  defp count_validations do
    DB.Repo.one!(from(r in DB.Validation, select: count()))
  end
end
