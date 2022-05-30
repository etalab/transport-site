defmodule TransportWeb.ValidationControllerTest do
  use TransportWeb.ConnCase, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Ecto.Query
  import Mox
  import Phoenix.LiveViewTest
  alias Transport.Test.S3TestUtils
  alias TransportWeb.Live.OnDemandValidationSelectLive

  setup :verify_on_exit!
  @gtfs_path "#{__DIR__}/../../fixture/files/gtfs.zip"
  @gtfs_rt_report_path "#{__DIR__}/../../fixture/files/gtfs-rt-validator-errors.json"
  @service_alerts_file "#{__DIR__}/../../fixture/files/bibus-brest-gtfs-rt-alerts.pb"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "GET /validation " do
    test "renders form", %{conn: conn} do
      Transport.Shared.Schemas.Mock |> expect(:transport_schemas, fn -> %{} end)
      conn |> get(live_path(conn, OnDemandValidationSelectLive)) |> html_response(200)
    end

    test "updates inputs", %{conn: conn} do
      Transport.Shared.Schemas.Mock |> expect(:transport_schemas, 2, fn -> %{} end)
      {:ok, view, _html} = conn |> get(live_path(conn, OnDemandValidationSelectLive)) |> live()
      assert view |> has_element?("input[name='upload[file]']")
      refute view |> has_element?("input[name='upload[url]']")

      render_change(view, "form_changed", %{"upload" => %{"type" => "gbfs"}})
      assert_patched(view, live_path(conn, OnDemandValidationSelectLive, type: "gbfs"))
      assert view |> has_element?("input[name='upload[url]']")
      refute view |> has_element?("input[name='upload[file]']")

      render_change(view, "form_changed", %{"upload" => %{"type" => "gtfs"}})
      assert_patched(view, live_path(conn, OnDemandValidationSelectLive, type: "gtfs"))
      refute view |> has_element?("input[name='upload[url]']")
      assert view |> has_element?("input[name='upload[file]']")

      render_change(view, "form_changed", %{"upload" => %{"type" => "gtfs-rt"}})
      assert view |> has_element?("input[name='upload[url]']")
      assert view |> has_element?("input[name='upload[feed_url]']")
    end

    test "takes into account query params", %{conn: conn} do
      Transport.Shared.Schemas.Mock |> expect(:transport_schemas, 2, fn -> %{} end)

      {:ok, view, _html} = conn |> get(live_path(conn, OnDemandValidationSelectLive, type: "gbfs")) |> live()
      refute view |> has_element?("input[name='upload[file]']")
      assert view |> has_element?("input[name='upload[url]']")
    end
  end

  describe "POST validate" do
    test "with a GBFS", %{conn: conn} do
      conn =
        conn
        |> post(validation_path(conn, :validate), %{
          "upload" => %{"url" => url = "https://example.com/gbfs.json", "type" => "gbfs"}
        })

      assert redirected_to(conn, 302) == gbfs_analyzer_path(conn, :index, url: url)

      validator_name = Transport.GBFSMetadata.validator_name()

      assert %{
               validator: ^validator_name,
               validated_data_name: ^url,
               validation_timestamp: validation_timestamp
             } = DB.Repo.one!(DB.MultiValidation)

      refute is_nil(validation_timestamp)
    end

    test "with a GTFS", %{conn: conn} do
      Transport.Shared.Schemas.Mock |> expect(:transport_schemas, fn -> %{} end)
      S3TestUtils.s3_mocks_upload_file("")
      assert 0 == count_validations()

      conn =
        conn
        |> post(validation_path(conn, :validate), %{
          "upload" => %{"file" => %Plug.Upload{path: @gtfs_path}, "type" => "gtfs"}
        })

      assert 1 == count_validations()

      assert %{
               oban_args: %{
                 "filename" => filename,
                 "permanent_url" => permanent_url,
                 "state" => "waiting",
                 "type" => "gtfs",
                 "secret_url_token" => token
               },
               id: validation_id
             } = DB.Repo.one!(DB.MultiValidation)

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
             ] = all_enqueued(worker: Transport.Jobs.OnDemandValidationJob, queue: :on_demand_validation)

      assert permanent_url == Transport.S3.permanent_url(:on_demand_validation, filename)
      assert redirected_to(conn, 302) == validation_path(conn, :show, validation_id, token: token)
    end

    test "with a schema", %{conn: conn} do
      schema_name = "etalab/foo"

      Transport.Shared.Schemas.Mock
      |> expect(:transport_schemas, 2, fn -> %{schema_name => %{"schema_type" => "tableschema", "title" => "foo"}} end)

      S3TestUtils.s3_mocks_upload_file("")
      assert 0 == count_validations()

      conn =
        conn
        |> post(validation_path(conn, :validate), %{
          "upload" => %{"file" => %Plug.Upload{path: @gtfs_path}, "type" => schema_name}
        })

      assert 1 == count_validations()

      assert %{
               oban_args: %{
                 "filename" => filename,
                 "permanent_url" => permanent_url,
                 "state" => "waiting",
                 "type" => "tableschema",
                 "schema_name" => ^schema_name
               },
               id: validation_id
             } = DB.Repo.one!(DB.MultiValidation)

      assert String.ends_with?(filename, ".csv")
      assert permanent_url == Transport.S3.permanent_url(:on_demand_validation, filename)

      assert [
               %Oban.Job{
                 args: %{
                   "id" => ^validation_id,
                   "state" => "waiting",
                   "filename" => ^filename,
                   "permanent_url" => ^permanent_url,
                   "type" => "tableschema",
                   "schema_name" => ^schema_name,
                   "secret_url_token" => token
                 }
               }
             ] = all_enqueued(worker: Transport.Jobs.OnDemandValidationJob, queue: :on_demand_validation)

      assert redirected_to(conn, 302) == validation_path(conn, :show, validation_id, token: token)
    end

    test "with a GTFS-RT", %{conn: conn} do
      gtfs_url = "https://example.com/gtfs.zip"
      gtfs_rt_url = "https://example.com/gtfs-rt"
      upload_params = %{"type" => "gtfs-rt", "url" => gtfs_url, "feed_url" => gtfs_rt_url}

      conn = conn |> post(validation_path(conn, :validate), %{"upload" => upload_params})

      assert 1 == count_validations()

      assert %{
               oban_args: %{
                 "gtfs_url" => ^gtfs_url,
                 "gtfs_rt_url" => ^gtfs_rt_url,
                 "state" => "waiting",
                 "type" => "gtfs-rt",
                 "secret_url_token" => token
               },
               id: validation_id,
               validation_timestamp: date
             } = DB.Repo.one!(DB.MultiValidation)

      refute is_nil(date)

      assert [
               %Oban.Job{
                 args: %{
                   "id" => ^validation_id,
                   "gtfs_url" => ^gtfs_url,
                   "gtfs_rt_url" => ^gtfs_rt_url,
                   "type" => "gtfs-rt"
                 }
               }
             ] = all_enqueued(worker: Transport.Jobs.OnDemandValidationJob, queue: :on_demand_validation)

      assert redirected_to(conn, 302) == validation_path(conn, :show, validation_id, token: token)

      # Submitting the same GTFS/GTFS-RT should not enqueue another job
      conn = conn |> post(validation_path(conn, :validate), %{"upload" => upload_params})

      assert redirected_to(conn, 302) ==
               live_path(conn, OnDemandValidationSelectLive, feed_url: gtfs_rt_url, type: "gtfs-rt", url: gtfs_url)

      assert Enum.count(all_enqueued(worker: Transport.Jobs.OnDemandValidationJob, queue: :on_demand_validation)) == 1

      assert %{
               oban_args: %{
                 "gtfs_url" => ^gtfs_url,
                 "gtfs_rt_url" => ^gtfs_rt_url,
                 "state" => "error",
                 "error_reason" => "Can run this job only once every 5 minutes",
                 "type" => "gtfs-rt"
               }
             } = DB.MultiValidation |> last() |> DB.Repo.one!()
    end

    test "with an invalid type", %{conn: conn} do
      Transport.Shared.Schemas.Mock |> expect(:transport_schemas, fn -> %{} end)

      conn
      |> post(validation_path(conn, :validate), %{
        "upload" => %{"file" => %Plug.Upload{path: @gtfs_path}, "type" => "foo"}
      })
      |> html_response(400)

      assert 0 == count_validations()
    end
  end

  describe "GET /validation/:id" do
    test "401 when validation with a token and the passed one doesn't match", %{conn: conn} do
      validation =
        insert(:multi_validation,
          oban_args: %{
            "state" => "waiting",
            "type" => "etalab/foo",
            "secret_url_token" => Ecto.UUID.generate()
          }
        )

      conn |> get(validation_path(conn, :show, validation.id)) |> html_response(401)
      conn |> get(validation_path(conn, :show, validation.id, token: "not-valid")) |> html_response(401)
    end

    test "validation without a token can be accessed", %{conn: conn} do
      validation = insert(:multi_validation, oban_args: %{"state" => "waiting", "type" => "etalab/foo"})

      refute Map.has_key?(validation.oban_args, "secret_url_token")

      conn |> get(validation_path(conn, :show, validation.id)) |> html_response(200)
    end

    test "with an unknown validation", %{conn: conn} do
      conn |> get(validation_path(conn, :show, 42)) |> html_response(404)
    end

    test "with an error", %{conn: conn} do
      {conn, validation} = ensure_waiting_message_is_displayed(conn, %{"state" => "waiting", "type" => "etalab/foo"})
      {:ok, view, _html} = live(conn)

      # Error message is displayed
      error_msg = "hello world"

      validation
      |> Ecto.Changeset.change(
        oban_args: Map.merge(validation.oban_args, %{"state" => "error", "error_reason" => error_msg})
      )
      |> DB.Repo.update!()

      send(view.pid, :update_data)
      assert render(view) =~ error_msg
    end

    test "with an error for a GTFS", %{conn: conn} do
      {conn, validation} = ensure_waiting_message_is_displayed(conn, %{"state" => "waiting", "type" => "gtfs"})
      {:ok, view, _html} = live(conn)

      # Error message is displayed
      error_msg = "hello world"

      validation
      |> Ecto.Changeset.change(
        oban_args: Map.merge(validation.oban_args, %{"state" => "error", "error_reason" => error_msg})
      )
      |> DB.Repo.update!()

      send(view.pid, :update_data)
      assert render(view) =~ error_msg
    end

    test "with a waiting validation", %{conn: conn} do
      {conn, validation} = ensure_waiting_message_is_displayed(conn, %{"state" => "waiting", "type" => "gtfs"})

      # Redirects to result's page when validation is done
      {:ok, view, _html} = live(conn)

      validation
      |> Ecto.Changeset.change(oban_args: Map.merge(validation.oban_args, %{"state" => "completed"}))
      |> DB.Repo.update!()

      send(view.pid, :update_data)

      assert_redirect(
        view,
        validation_path(conn, :show, validation.id, token: Map.fetch!(validation.oban_args, "secret_url_token"))
      )
    end

    test "with a validation result", %{conn: conn} do
      schema_name = "etalab/foo"

      Transport.Shared.Schemas.Mock
      |> expect(:transport_schemas, fn ->
        %{
          schema_name => %{
            "versions" => [%{"version_name" => "0.1.0", "schema_url" => "http://example.com/schema.json"}]
          }
        }
      end)

      {conn, validation} = ensure_waiting_message_is_displayed(conn, %{"state" => "waiting", "type" => schema_name})
      {:ok, view, _html} = live(conn)

      # Error messages are displayed
      validation
      |> Ecto.Changeset.change(
        oban_args:
          Map.merge(validation.oban_args, %{
            "state" => "completed",
            "type" => "tableschema",
            "schema_name" => schema_name
          }),
        result: %{
          "errors" => [
            "#/features/0/properties/deux_rm_critair: Value is not allowed in enum.",
            "#/features/0/properties/vp_critair: Value is not allowed in enum."
          ],
          "has_errors" => true,
          errors_count: 2
        }
      )
      |> DB.Repo.update!()

      send(view.pid, :update_data)

      assert render(view) =~ "2 erreurs"
      assert render(view) =~ "Value is not allowed in enum."
    end

    test "with a GTFS-RT validation", %{conn: conn} do
      gtfs_rt_url = "https://example.com/gtfs-rt"

      Transport.HTTPoison.Mock
      |> expect(:get, fn ^gtfs_rt_url, [], [follow_redirect: true] ->
        {:ok, %HTTPoison.Response{status_code: 200, body: File.read!(@service_alerts_file)}}
      end)

      {conn, validation} =
        ensure_waiting_message_is_displayed(conn, %{
          "state" => "waiting",
          "type" => "gtfs-rt",
          "gtfs_url" => "https://example.com/gtfs.zip",
          "gtfs_rt_url" => gtfs_rt_url
        })

      {:ok, view, _html} = live(conn)

      # Validation is displayed
      {:ok, report} = Transport.Jobs.GTFSRTValidationJob.convert_validator_report(@gtfs_rt_report_path)

      validation
      |> Ecto.Changeset.change(
        oban_args: %{validation.oban_args | "state" => "completed"},
        result: report
      )
      |> DB.Repo.update!()

      send(view.pid, :update_data)

      assert render(view) =~ "4 erreurs, 26 avertissements"
      assert render(view) =~ "stop_times_updates not strictly sorted"
      assert render(view) =~ "vehicle_id should be populated for TripUpdates and VehiclePositions"
      assert render(view) =~ "Ligne 5 Travaux à compter 22/11 pour 5 semaines"
    end
  end

  defp ensure_waiting_message_is_displayed(conn, metadata) do
    validation =
      insert(:multi_validation,
        oban_args: Map.merge(metadata, %{"secret_url_token" => Ecto.UUID.generate()})
      )

    conn =
      conn
      |> get(validation_path(conn, :show, validation.id, token: Map.fetch!(validation.oban_args, "secret_url_token")))

    # Displays the waiting message
    response = html_response(conn, 200)
    assert response =~ "Validation en cours."

    {conn, validation}
  end

  defp count_validations do
    DB.Repo.one!(from(v in DB.MultiValidation, select: count()))
  end
end
