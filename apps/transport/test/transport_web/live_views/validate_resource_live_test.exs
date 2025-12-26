defmodule Transport.TransportWeb.Live.ValidateResourceLiveTest do
  use TransportWeb.ConnCase, async: true
  use Oban.Testing, repo: DB.Repo
  import Phoenix.LiveViewTest

  @gtfs_path "#{__DIR__}/../../fixture/files/gtfs.zip"

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "success case for a GTFS", %{conn: conn} do
    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.ValidateResourceLive, session: %{"locale" => "fr"})

    assert [
             {"input",
              [
                {"id", _},
                {"type", "file"},
                {"name", "gtfs"},
                {"accept", ".zip"},
                {"data-phx-hook", "Phoenix.LiveFileUpload"},
                {"data-phx-update", "ignore"},
                {"data-phx-upload-ref", _},
                {"data-phx-active-refs", ""},
                {"data-phx-done-refs", ""},
                {"data-phx-preflighted-refs", ""},
                {"data-phx-auto-upload", "data-phx-auto-upload"}
              ], []}
           ] = render(view) |> Floki.parse_document!() |> Floki.find(~s|input[type="file"]|)

    Transport.Test.S3TestUtils.s3_mock_stream_file(
      start_path: "",
      bucket: "transport-data-gouv-fr-on-demand-validation-test"
    )

    content = upload_file(view)

    # Loading state
    assert_loading_state(content)

    # Validation has been created
    assert [
             %DB.MultiValidation{
               oban_args: %{
                 "filename" => filename,
                 "permanent_url" => permanent_url,
                 "secret_url_token" => _,
                 "state" => "waiting",
                 "type" => "gtfs"
               }
             } = multi_validation
           ] = DB.Repo.all(DB.MultiValidation)

    assert permanent_url == Transport.S3.permanent_url(:on_demand_validation, filename)

    # Job has been enqueued
    oban_args = Map.put(multi_validation.oban_args, "id", multi_validation.id)

    assert [
             %Oban.Job{
               state: "available",
               args: ^oban_args,
               queue: "on_demand_validation",
               worker: "Transport.Jobs.OnDemandValidationJob"
             }
           ] = all_enqueued()

    # Update the validation to mimick success
    multi_validation
    |> DB.Repo.preload(:metadata)
    |> Ecto.Changeset.change(%{
      oban_args: Map.put(multi_validation.oban_args, "state", "completed"),
      max_error: "Warning",
      metadata: %DB.ResourceMetadata{metadata: %{"start_date" => "2025-01-01", "end_date" => "2025-01-31"}}
    })
    |> DB.Repo.update!()

    send(view.pid, :update_data)
    content = render(view) |> Floki.parse_document!()

    # Success is displayed
    assert [
             {
               "p",
               [{"class", "notification success"}],
               ["\n  Pas d'erreurs\n"]
             }
           ] = content |> Floki.find(".notification")

    # Validity period is displayed
    assert content |> Floki.find(~s|[title="Période de validité"]|) == [
             {
               "div",
               [{"title", "Période de validité"}],
               [
                 {"i", [{"class", "icon icon--calendar-alt"}, {"aria-hidden", "true"}], []},
                 {"span", [], ["01/01/2025"]},
                 {"i", [{"class", "icon icon--right-arrow ml-05-em"}, {"aria-hidden", "true"}], []},
                 {"span", [{"class", "resource__summary--Error"}], ["31/01/2025"]}
               ]
             }
           ]

    # Link to see the validation report
    assert_validation_report_link(content, multi_validation)

    # Hidden inputs are present
    assert [
             {"input", [{"type", "hidden"}, {"name", "resource_file[filename]"}, {"value", "gtfs.zip"}], []},
             {"input", [{"type", "hidden"}, {"name", "resource_file[path]"}, {"value", _}], []}
           ] = content |> Floki.find("input")
  end

  test "error case for a GTFS", %{conn: conn} do
    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.ValidateResourceLive, session: %{"locale" => "fr"})

    Transport.Test.S3TestUtils.s3_mock_stream_file(
      start_path: "",
      bucket: "transport-data-gouv-fr-on-demand-validation-test"
    )

    content = upload_file(view)

    # Loading state
    assert_loading_state(content)

    # Validation has been created
    assert [
             %DB.MultiValidation{
               oban_args: %{
                 "filename" => filename,
                 "permanent_url" => permanent_url,
                 "secret_url_token" => _,
                 "state" => "waiting",
                 "type" => "gtfs"
               }
             } = multi_validation
           ] = DB.Repo.all(DB.MultiValidation)

    assert permanent_url == Transport.S3.permanent_url(:on_demand_validation, filename)

    # Job has been enqueued
    oban_args = Map.put(multi_validation.oban_args, "id", multi_validation.id)

    assert [
             %Oban.Job{
               state: "available",
               args: ^oban_args,
               queue: "on_demand_validation",
               worker: "Transport.Jobs.OnDemandValidationJob"
             }
           ] = all_enqueued()

    # Update the validation to mimick an error
    multi_validation
    |> DB.Repo.preload(:metadata)
    |> Ecto.Changeset.change(%{
      oban_args: Map.put(multi_validation.oban_args, "state", "completed"),
      max_error: "Error",
      metadata: %DB.ResourceMetadata{metadata: %{"start_date" => "2025-12-01", "end_date" => "2025-12-31"}}
    })
    |> DB.Repo.update!()

    send(view.pid, :update_data)
    content = render(view) |> Floki.parse_document!()

    # Error state is displayed
    assert [{"p", [{"class", "notification error"}], ["\n  Fichier invalide\n"]}] =
             content |> Floki.find(".notification")

    # Can start again
    assert content |> Floki.find(~s|[phx-click="start_again"]|) == [
             {"a", [{"phx-click", "start_again"}, {"class", "button-outline warning small mr-24"}],
              [{"i", [{"class", "icon fa fa-rotate"}], []}, "\n  Essayer à nouveau\n"]}
           ]

    # Link to see the validation report
    assert_validation_report_link(content, multi_validation)

    # Click on "Start again"
    view |> element(~s|[phx-click="start_again"]|) |> render_click()

    refute view |> has_element?(".notification")
    assert view |> has_element?(~s|input[type="file"|)
  end

  defp assert_validation_report_link(content, %DB.MultiValidation{
         id: id,
         oban_args: %{"secret_url_token" => secret_url_token}
       }) do
    assert content |> Floki.find(".button-outline.primary") == [
             {"a",
              [
                {"class", "button-outline primary small"},
                {"target", "_blank"},
                {"href", validation_path(TransportWeb.Endpoint, :show, id, token: secret_url_token)}
              ], [{"i", [{"class", "icon fa fa-pen-to-square"}], []}, "Voir le rapport de validation\n  "]}
           ]
  end

  defp assert_loading_state(content) do
    assert content =~ "Fichier : <strong>gtfs.zip</strong>"

    assert content |> Floki.parse_document!() |> Floki.find(".loader_container") == [
             {"div", [{"class", "loader_container"}], [{"div", [{"class", "loader"}], []}]}
           ]
  end

  defp upload_file(%Phoenix.LiveViewTest.View{} = view) do
    file_input(view, "#upload-form", :gtfs, [
      %{
        name: "gtfs.zip",
        content: File.read!(@gtfs_path)
      }
    ])
    |> render_upload("gtfs.zip")
  end
end
