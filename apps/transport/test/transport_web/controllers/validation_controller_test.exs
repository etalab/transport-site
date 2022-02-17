defmodule TransportWeb.ValidationControllerTest do
  use TransportWeb.ConnCase, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Ecto.Query
  import Mox
  import Phoenix.LiveViewTest
  alias Transport.Test.S3TestUtils

  setup :verify_on_exit!
  @gtfs_path "#{__DIR__}/../../fixture/files/gtfs.zip"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "GET /validation ", %{conn: conn} do
    Transport.Shared.Schemas.Mock |> expect(:transport_schemas, fn -> %{} end)
    conn |> get(validation_path(conn, :index)) |> html_response(200)
  end

  describe "POST validate" do
    test "with a GTFS", %{conn: conn} do
      Transport.Shared.Schemas.Mock |> expect(:transport_schemas, fn -> %{} end)
      S3TestUtils.s3_mocks_upload_file("")
      assert 0 == count_validations()

      conn =
        conn
        |> post(validation_path(conn, :index), %{
          "upload" => %{"file" => %Plug.Upload{path: @gtfs_path}, "type" => "gtfs"}
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
             ] = all_enqueued(worker: Transport.Jobs.OnDemandValidationJob, queue: :on_demand_validation)

      assert permanent_url == Transport.S3.permanent_url(:on_demand_validation, filename)
      assert redirected_to(conn, 302) =~ validation_path(conn, :show, validation_id)
    end

    test "with a schema", %{conn: conn} do
      schema_name = "etalab/foo"

      Transport.Shared.Schemas.Mock
      |> expect(:transport_schemas, 2, fn -> %{schema_name => %{"type" => "tableschema", "title" => "foo"}} end)

      S3TestUtils.s3_mocks_upload_file("")
      assert 0 == count_validations()

      conn =
        conn
        |> post(validation_path(conn, :index), %{
          "upload" => %{"file" => %Plug.Upload{path: @gtfs_path}, "type" => schema_name}
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
                   "schema_name" => ^schema_name
                 }
               }
             ] = all_enqueued(worker: Transport.Jobs.OnDemandValidationJob, queue: :on_demand_validation)

      assert redirected_to(conn, 302) =~ validation_path(conn, :show, validation_id)
    end

    test "with an invalid type", %{conn: conn} do
      Transport.Shared.Schemas.Mock |> expect(:transport_schemas, fn -> %{} end)

      conn
      |> post(validation_path(conn, :index), %{"upload" => %{"file" => %Plug.Upload{path: @gtfs_path}, "type" => "foo"}})
      |> html_response(400)

      assert 0 == count_validations()
    end
  end

  describe "GET /validation/:id" do
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
        on_the_fly_validation_metadata:
          Map.merge(validation.on_the_fly_validation_metadata, %{"state" => "error", "error_reason" => error_msg})
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
        on_the_fly_validation_metadata:
          Map.merge(validation.on_the_fly_validation_metadata, %{"state" => "error", "error_reason" => error_msg})
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
      |> Ecto.Changeset.change(
        on_the_fly_validation_metadata: Map.merge(validation.on_the_fly_validation_metadata, %{"state" => "completed"}),
        details: %{}
      )
      |> DB.Repo.update!()

      send(view.pid, :update_data)

      assert_redirect(view, validation_path(conn, :show, validation.id))
    end

    test "with a validation result", %{conn: conn} do
      schema_name = "etalab/foo"

      Transport.Shared.Schemas.Mock
      |> expect(:transport_schemas, fn ->
        %{schema_name => %{"versions" => [], "schemas" => [%{"path" => "schema.json"}]}}
      end)

      {conn, validation} = ensure_waiting_message_is_displayed(conn, %{"state" => "waiting", "type" => schema_name})
      {:ok, view, _html} = live(conn)

      # Error messages are displayed
      validation
      |> Ecto.Changeset.change(
        on_the_fly_validation_metadata:
          Map.merge(validation.on_the_fly_validation_metadata, %{
            "state" => "completed",
            "type" => "tableschema",
            "schema_name" => schema_name
          }),
        details: %{
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
  end

  defp ensure_waiting_message_is_displayed(conn, metadata) do
    validation = insert(:validation, on_the_fly_validation_metadata: metadata)
    conn = conn |> get(validation_path(conn, :show, validation.id))

    # Displays the waiting message
    response = html_response(conn, 200)
    assert response =~ "Validation en cours."

    {conn, validation}
  end

  defp count_validations do
    DB.Repo.one!(from(r in DB.Validation, select: count()))
  end
end
