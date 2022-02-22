defmodule Transport.Test.Transport.Jobs.OnDemandValidationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  import Transport.Test.S3TestUtils
  alias Transport.Jobs.OnDemandValidationJob

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  @url "https://example.com/file.zip"
  @filename "file.zip"

  describe "OnDemandValidationJob" do
    test "with a GTFS" do
      validation = create_validation(%{"type" => "gtfs"})

      Validation.Validator.Mock
      |> expect(:validate_from_url, fn url ->
        assert url == @url

        {:ok,
         %{
           "validations" => %{},
           "metadata" => %{
             "start_date" => "2021-12-04",
             "end_date" => "2022-04-24",
             "modes" => ["bus"],
             "networks" => ["Autocars RESALP"]
           }
         }}
      end)

      s3_mocks_delete_object(Transport.S3.bucket_name(:on_demand_validation), @filename)

      assert :ok == run_job(validation)

      assert %{
               date: date,
               details: %{},
               on_the_fly_validation_metadata: %{"state" => "completed", "type" => "gtfs", "modes" => ["bus"]},
               data_vis: %{}
             } = DB.Repo.reload(validation)

      assert {:ok, dt, 0} = DateTime.from_iso8601(date)
      assert DateTime.diff(dt, DateTime.utc_now()) <= 1
    end

    test "GTFS with an error" do
      validation = create_validation(%{"type" => "gtfs"})

      Validation.Validator.Mock
      |> expect(:validate_from_url, fn url ->
        assert url == @url
        {:error, "something happened"}
      end)

      s3_mocks_delete_object(Transport.S3.bucket_name(:on_demand_validation), @filename)

      assert :ok == run_job(validation)

      assert %{
               details: nil,
               on_the_fly_validation_metadata: %{
                 "state" => "error",
                 "error_reason" => "something happened",
                 "type" => "gtfs"
               },
               data_vis: nil
             } = DB.Repo.reload(validation)
    end

    test "with a tableschema" do
      schema_name = "etalab/foo"
      validation_result = %{"errors_count" => 0, "has_errors" => false, "errors" => []}

      validation = create_validation(%{"type" => "tableschema", "schema_name" => schema_name})

      Shared.Validation.TableSchemaValidator.Mock
      |> expect(:validate, fn ^schema_name, url ->
        assert url == @url
        validation_result
      end)

      s3_mocks_delete_object(Transport.S3.bucket_name(:on_demand_validation), @filename)

      assert :ok == run_job(validation)

      assert %{
               details: ^validation_result,
               on_the_fly_validation_metadata: %{
                 "state" => "completed",
                 "type" => "tableschema",
                 "schema_name" => ^schema_name
               },
               data_vis: nil
             } = DB.Repo.reload(validation)
    end

    test "with a jsonschema" do
      schema_name = "etalab/foo"
      validation_result = %{"errors_count" => 0, "has_errors" => false, "errors" => []}

      validation = create_validation(%{"type" => "jsonschema", "schema_name" => schema_name})

      Shared.Validation.JSONSchemaValidator.Mock
      |> expect(:load_jsonschema_for_schema, fn ^schema_name ->
        %ExJsonSchema.Schema.Root{
          schema: %{"properties" => %{"name" => %{"type" => "string"}}, "required" => ["name"], "type" => "object"},
          version: 7
        }
      end)

      Shared.Validation.JSONSchemaValidator.Mock
      |> expect(:validate, fn _schema, url ->
        assert url == @url
        validation_result
      end)

      s3_mocks_delete_object(Transport.S3.bucket_name(:on_demand_validation), @filename)

      assert :ok == run_job(validation)

      assert %{
               details: ^validation_result,
               on_the_fly_validation_metadata: %{
                 "state" => "completed",
                 "type" => "jsonschema",
                 "schema_name" => ^schema_name
               },
               data_vis: nil
             } = DB.Repo.reload(validation)
    end

    test "jsonschema with an exception raised" do
      schema_name = "etalab/foo"

      validation = create_validation(%{"type" => "jsonschema", "schema_name" => schema_name})

      Shared.Validation.JSONSchemaValidator.Mock
      |> expect(:load_jsonschema_for_schema, fn ^schema_name ->
        raise "not a valid schema"
      end)

      s3_mocks_delete_object(Transport.S3.bucket_name(:on_demand_validation), @filename)

      assert :ok == run_job(validation)

      assert %{
               details: nil,
               on_the_fly_validation_metadata: %{
                 "state" => "error",
                 "type" => "jsonschema",
                 "schema_name" => ^schema_name
               },
               data_vis: nil
             } = DB.Repo.reload(validation)
    end
  end

  defp create_validation(details) do
    metadata = Map.merge(%{"state" => "waiting", "permanent_url" => @url, "filename" => @filename}, details)
    insert(:validation, on_the_fly_validation_metadata: metadata)
  end

  defp run_job(%DB.Validation{} = validation) do
    payload = Map.merge(%{"id" => validation.id}, validation.on_the_fly_validation_metadata)
    perform_job(OnDemandValidationJob, payload)
  end
end
