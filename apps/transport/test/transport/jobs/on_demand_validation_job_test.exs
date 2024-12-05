defmodule Transport.Test.Transport.Jobs.OnDemandValidationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  import Transport.Test.EnRouteChouetteValidClientHelpers
  import Transport.Test.S3TestUtils
  alias Transport.Jobs.OnDemandValidationJob
  alias Transport.Validators.GTFSRT

  setup :verify_on_exit!

  setup do
    Mox.stub_with(Transport.DataVisualization.Mock, Transport.DataVisualization.Impl)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  @url "https://example.com/file.zip"
  @filename "file.zip"
  @gtfs_rt_report_path "#{__DIR__}/../../fixture/files/gtfs-rt-validator-errors.json"
  @validator_filename "gtfs-realtime-validator-lib-1.0.0-SNAPSHOT.jar"

  describe "OnDemandValidationJob" do
    test "with a GTFS" do
      validation = create_validation(%{"type" => "gtfs"})

      Shared.Validation.Validator.Mock
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
               validation_timestamp: date,
               result: %{},
               oban_args: %{"state" => "completed", "type" => "gtfs"},
               metadata: %{metadata: %{"modes" => ["bus"]}},
               data_vis: %{}
             } = validation |> DB.Repo.reload() |> DB.Repo.preload(:metadata)

      assert DateTime.diff(date, DateTime.utc_now()) <= 1
    end

    test "GTFS with an error" do
      validation = create_validation(%{"type" => "gtfs"})

      Shared.Validation.Validator.Mock
      |> expect(:validate_from_url, fn url ->
        assert url == @url
        {:error, "something happened"}
      end)

      s3_mocks_delete_object(Transport.S3.bucket_name(:on_demand_validation), @filename)

      assert :ok == run_job(validation)

      assert %{
               result: nil,
               oban_args: %{
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
               result: ^validation_result,
               oban_args: %{
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
               result: ^validation_result,
               oban_args: %{
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
               result: nil,
               oban_args: %{
                 "state" => "error",
                 "type" => "jsonschema",
                 "schema_name" => ^schema_name
               },
               data_vis: nil
             } = DB.Repo.reload(validation)
    end

    test "with a gtfs-rt" do
      gtfs_url = "https://example.com/gtfs.zip"
      gtfs_rt_url = "https://example.com/gtfs-rt"
      validation = create_validation(%{"type" => "gtfs-rt", "gtfs_url" => gtfs_url, "gtfs_rt_url" => gtfs_rt_url})

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^gtfs_url, [], _ ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "gtfs"}}
      end)

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^gtfs_rt_url, [], _ ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "gtfs-rt"}}
      end)

      gtfs_path = OnDemandValidationJob.filename(validation.id, "gtfs")
      gtfs_rt_path = OnDemandValidationJob.filename(validation.id, "gtfs-rt")

      Transport.Rambo.Mock
      |> expect(:run, fn binary, args, [log: false] ->
        assert binary == "java"
        assert File.exists?(gtfs_path)
        assert File.exists?(gtfs_rt_path)

        assert [
                 "-jar",
                 validator_path(),
                 "-gtfs",
                 gtfs_path,
                 "-gtfsRealtimePath",
                 Path.dirname(gtfs_rt_path)
               ] == args

        File.write!(OnDemandValidationJob.gtfs_rt_result_path(gtfs_rt_path), File.read!(@gtfs_rt_report_path))
        {:ok, nil}
      end)

      assert :ok == run_job(validation)

      {:ok, expected_details} = GTFSRT.convert_validator_report(@gtfs_rt_report_path)

      assert %{
               result: ^expected_details,
               oban_args: %{
                 "state" => "completed",
                 "type" => "gtfs-rt",
                 "gtfs_url" => ^gtfs_url,
                 "gtfs_rt_url" => ^gtfs_rt_url
               },
               data_vis: nil
             } = DB.Repo.reload(validation)

      refute File.exists?(gtfs_path)
      refute File.exists?(gtfs_rt_path)
      refute File.exists?(OnDemandValidationJob.gtfs_rt_result_path(gtfs_rt_path))
    end

    test "with a gtfs-rt, cannot download GTFS" do
      gtfs_url = "https://example.com/gtfs.zip"
      gtfs_rt_url = "https://example.com/gtfs-rt"
      validation = create_validation(%{"type" => "gtfs-rt", "gtfs_url" => gtfs_url, "gtfs_rt_url" => gtfs_rt_url})

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^gtfs_url, [], _ ->
        {:ok, %HTTPoison.Response{status_code: 404}}
      end)

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^gtfs_rt_url, [], _ ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "gtfs-rt"}}
      end)

      assert :ok == run_job(validation)

      expected_error_reason = "Got a non 200 status: 404 when downloading #{gtfs_url}"

      assert %{
               result: nil,
               oban_args: %{
                 "state" => "error",
                 "error_reason" => ^expected_error_reason,
                 "type" => "gtfs-rt",
                 "gtfs_url" => ^gtfs_url,
                 "gtfs_rt_url" => ^gtfs_rt_url
               },
               data_vis: nil
             } = DB.Repo.reload(validation)

      gtfs_path = OnDemandValidationJob.filename(validation.id, "gtfs")
      gtfs_rt_path = OnDemandValidationJob.filename(validation.id, "gtfs-rt")
      refute File.exists?(gtfs_path)
      refute File.exists?(gtfs_rt_path)
    end

    test "with a gtfs-rt, validator error" do
      gtfs_url = "https://example.com/gtfs.zip"
      gtfs_rt_url = "https://example.com/gtfs-rt"
      validation = create_validation(%{"type" => "gtfs-rt", "gtfs_url" => gtfs_url, "gtfs_rt_url" => gtfs_rt_url})

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^gtfs_url, [], _ ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "gtfs"}}
      end)

      gtfs_path = OnDemandValidationJob.filename(validation.id, "gtfs")
      gtfs_rt_path = OnDemandValidationJob.filename(validation.id, "gtfs-rt")

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^gtfs_rt_url, [], _ ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "gtfs-rt"}}
      end)

      Transport.Rambo.Mock
      |> expect(:run, fn binary, args, [log: false] ->
        assert binary == "java"
        assert File.exists?(gtfs_path)
        assert File.exists?(gtfs_rt_path)

        assert [
                 "-jar",
                 validator_path(),
                 "-gtfs",
                 gtfs_path,
                 "-gtfsRealtimePath",
                 Path.dirname(gtfs_rt_path)
               ] == args

        {:error, "validator error"}
      end)

      assert :ok == run_job(validation)

      assert %{
               result: nil,
               oban_args: %{
                 "state" => "error",
                 "error_reason" => ~s("validator error"),
                 "type" => "gtfs-rt",
                 "gtfs_url" => ^gtfs_url,
                 "gtfs_rt_url" => ^gtfs_rt_url
               },
               data_vis: nil
             } = DB.Repo.reload(validation)

      refute File.exists?(gtfs_path)
      refute File.exists?(gtfs_rt_path)
    end

    test "with a gtfs-rt, validation fails, retries without shapes" do
      gtfs_url = "https://example.com/gtfs.zip"
      gtfs_rt_url = "https://example.com/gtfs-rt"
      validation = create_validation(%{"type" => "gtfs-rt", "gtfs_url" => gtfs_url, "gtfs_rt_url" => gtfs_rt_url})

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^gtfs_url, [], _ ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "gtfs"}}
      end)

      gtfs_path = OnDemandValidationJob.filename(validation.id, "gtfs")
      gtfs_rt_path = OnDemandValidationJob.filename(validation.id, "gtfs-rt")

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^gtfs_rt_url, [], _ ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "gtfs-rt"}}
      end)

      Transport.Rambo.Mock
      |> expect(:run, fn binary, args, [log: false] ->
        assert binary == "java"
        assert File.exists?(gtfs_path)
        assert File.exists?(gtfs_rt_path)

        assert [
                 "-jar",
                 validator_path(),
                 "-gtfs",
                 gtfs_path,
                 "-gtfsRealtimePath",
                 Path.dirname(gtfs_rt_path)
               ] == args

        {:error, "Exception in thread main java.lang.OutOfMemoryError: Java heap space"}
      end)

      Transport.Rambo.Mock
      |> expect(:run, fn binary, args, [log: false] ->
        assert binary == "java"
        assert File.exists?(gtfs_path)
        assert File.exists?(gtfs_rt_path)

        assert [
                 "-jar",
                 validator_path(),
                 "-ignoreShapes",
                 "yes",
                 "-gtfs",
                 gtfs_path,
                 "-gtfsRealtimePath",
                 Path.dirname(gtfs_rt_path)
               ] == args

        File.write!(OnDemandValidationJob.gtfs_rt_result_path(gtfs_rt_path), File.read!(@gtfs_rt_report_path))
        {:ok, nil}
      end)

      assert :ok == run_job(validation)

      {:ok, expected_details} = GTFSRT.convert_validator_report(@gtfs_rt_report_path, ignore_shapes: true)

      assert %{
               result: ^expected_details,
               oban_args: %{
                 "state" => "completed",
                 "type" => "gtfs-rt",
                 "gtfs_url" => ^gtfs_url,
                 "gtfs_rt_url" => ^gtfs_rt_url
               },
               data_vis: nil
             } = DB.Repo.reload(validation)

      refute File.exists?(gtfs_path)
      refute File.exists?(gtfs_rt_path)
      refute File.exists?(OnDemandValidationJob.gtfs_rt_result_path(gtfs_rt_path))
    end

    test "with a NeTEx with errors" do
      url = mk_raw_netex_resource()
      validation = create_validation(%{"type" => "netex"}, url)

      errors = [
        %{
          "code" => "xsd-1871",
          "criticity" => "error",
          "message" =>
            "Element '{http://www.netex.org.uk/netex}OppositeDIrectionRef': This element is not expected. Expected is ( {http://www.netex.org.uk/netex}OppositeDirectionRef )."
        },
        %{
          "code" => "uic-operating-period",
          "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod",
          "criticity" => "error"
        },
        %{
          "code" => "valid-day-bits",
          "message" => "Mandatory attribute valid_day_bits not found",
          "criticity" => "error"
        },
        %{
          "code" => "frame-arret-resources",
          "message" => "Tag frame_id doesn't match ''",
          "criticity" => "warning"
        }
      ]

      expect_netex_with_errors(errors)

      s3_mocks_delete_object(Transport.S3.bucket_name(:on_demand_validation), @filename)

      assert :ok == run_job(validation)

      assert %{
               validation_timestamp: date,
               result: result,
               max_error: "error",
               oban_args: %{"state" => "completed", "type" => "netex"},
               metadata: %{},
               data_vis: nil
             } = validation |> DB.Repo.reload() |> DB.Repo.preload(:metadata)

      assert %{"xsd-1871" => a1, "uic-operating-period" => a2, "valid-day-bits" => a3, "frame-arret-resources" => a4} =
               result

      assert length(a1) == 1
      assert length(a2) == 1
      assert length(a3) == 1
      assert length(a4) == 1

      assert DateTime.diff(date, DateTime.utc_now()) <= 1
    end

    test "with a NeTEx long lasting" do
      url = mk_raw_netex_resource()
      validation = create_validation(%{"type" => "netex"}, url)

      validation_id = expect_netex_long_lasting()

      s3_mocks_delete_object(Transport.S3.bucket_name(:on_demand_validation), @filename)

      assert :ok == run_job(validation)

      validation = DB.Repo.reload(validation)
      assert nil == validation.result
      assert nil == validation.max_error

      assert %{
               "filename" => @filename,
               "permanent_url" => url,
               "type" => "netex",
               "state" => "waiting"
             } = validation.oban_args

      in_20_seconds = DateTime.utc_now() |> DateTime.add(20, :second)

      assert_enqueued(
        worker: Transport.Jobs.OnDemandNeTExPollerJob,
        args: %{
          "id" => validation.id,
          "permanent_url" => url,
          "validation_id" => validation_id
        },
        scheduled_at: in_20_seconds
      )
    end
  end

  defp create_validation(details, url \\ @url) do
    details =
      if details["type"] == "gtfs-rt" do
        details
      else
        Map.merge(details, %{"filename" => @filename, "permanent_url" => url})
      end

    oban_args = Map.merge(%{"state" => "waiting"}, details)

    insert(:multi_validation, oban_args: oban_args)
  end

  def expect_netex_with_errors(messages) do
    validation_id = expect_create_validation()
    expect_failed_validation(validation_id, 10)

    expect_get_messages(validation_id, messages)
  end

  def expect_netex_long_lasting do
    expect_create_validation() |> expect_pending_validation()
  end

  defp run_job(%DB.MultiValidation{} = validation) do
    payload = Map.merge(%{"id" => validation.id}, validation.oban_args)
    perform_job(OnDemandValidationJob, payload)
  end

  defp validator_path, do: Path.join(Application.fetch_env!(:transport, :transport_tools_folder), @validator_filename)

  defp mk_raw_netex_resource do
    resource_url = "http://localhost:9999/netex-#{Ecto.UUID.generate()}.zip"

    expect(Transport.Req.Mock, :get!, 1, fn ^resource_url, [{:compressed, false}, {:into, _}] ->
      {:ok, %Req.Response{status: 200, body: %{"data" => "some_zip_file"}}}
    end)

    resource_url
  end
end
