defmodule TransportWeb.Backoffice.ProxyConfigLiveTest do
  use ExUnit.Case, async: true
  use TransportWeb.LiveCase
  import TransportWeb.ConnCase, only: [setup_admin_in_session: 1]
  import Mox
  import Phoenix.LiveViewTest

  doctest TransportWeb.Backoffice.ProxyConfigLive, import: true

  @endpoint TransportWeb.Endpoint
  @url "/backoffice/proxy-config"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    DB.Repo.delete_all(DB.Metrics)
    {:ok, conn: build_conn()}
  end

  setup :verify_on_exit!

  def setup_proxy_config(slug, siri_slug, aggregate_slug, s3_slug) do
    config = %{
      slug => %Unlock.Config.Item.Generic.HTTP{
        identifier: slug,
        target_url: "http://localhost/some-remote-resource",
        ttl: 10
      },
      siri_slug => %Unlock.Config.Item.SIRI{
        identifier: siri_slug,
        target_url: "http://localhost/some-siri-resource",
        requestor_ref: "secret"
      },
      aggregate_slug => %Unlock.Config.Item.Aggregate{
        identifier: aggregate_slug,
        feeds: []
      },
      s3_slug => %Unlock.Config.Item.S3{
        identifier: s3_slug,
        bucket: "bucket",
        path: "path",
        ttl: 500
      }
    }

    Unlock.Config.Fetcher.Mock
    |> stub(:fetch_config!, fn -> config end)
  end

  test "requires login", %{conn: conn} do
    conn = get(conn, @url)
    assert html_response(conn, 302)
  end

  def add_events(item_id) do
    target = "proxy:#{item_id}"
    Transport.Telemetry.count_event(target, event_name(:external))
    Transport.Telemetry.count_event(target, event_name(:external))
    Transport.Telemetry.count_event(target, event_name(:internal))
  end

  defp event_name(type) do
    type |> Transport.Telemetry.proxy_request_event_name()
  end

  test "disconnected and connected mount refresh stats", %{conn: conn} do
    item_id = "gtfs-rt-slug"
    siri_item_id = "siri-slug"
    aggregate_item_id = "aggregate-slug"
    s3_item_id = "s3-slug"
    setup_proxy_config(item_id, siri_item_id, aggregate_item_id, s3_item_id)

    add_events(item_id)

    conn = setup_admin_in_session(conn)
    conn = get(conn, @url)

    response = html_response(conn, 200)
    assert response =~ "Configuration du Proxy"

    # NOTE: alphabetical slug order
    assert [
             %{
               "Type" => "Aggregate",
               "Identifiant" => "aggregate-slug",
               "Req ext 7j" => "0",
               "Req int 7j" => "N/C"
             },
             %{
               "Type" => "HTTP",
               "Identifiant" => "gtfs-rt-slug",
               "Req ext 7j" => "2",
               "Req int 7j" => "1"
             },
             %{
               "Type" => "S3",
               "Identifiant" => "s3-slug",
               "Req ext 7j" => "0",
               "Req int 7j" => "0"
             },
             %{
               "Identifiant" => "siri-slug",
               "Req ext 7j" => "0",
               "Req int 7j" => "0"
             }
           ] = extract_data_from_html(response)

    {:ok, view, _html} = live(conn)

    add_events(item_id)

    send(view.pid, :update_data)

    assert [
             _aggregate_item,
             %{
               "Type" => "HTTP",
               "Identifiant" => "gtfs-rt-slug",
               "Req ext 7j" => "4",
               "Req int 7j" => "2"
             },
             _siri_item,
             _s3_item
           ] = extract_data_from_html(render(view))
  end

  test "can search feeds", %{conn: conn} do
    item_id = "gtfs-rt-slug"
    siri_item_id = "siri-slug"
    aggregate_item_id = "aggregate-slug"
    s3_item_id = "s3-slug"
    setup_proxy_config(item_id, siri_item_id, aggregate_item_id, s3_item_id)

    {:ok, view, _html} = conn |> setup_admin_in_session() |> get(@url) |> live()

    assert [
             {"select", [{"id", "backoffice_search_container_type"}, {"name", "type"}],
              [
                {"option", [{"selected", "selected"}, {"value", ""}], ["Tout"]},
                {"option", [{"value", "Aggregate"}], ["Aggregate"]},
                {"option", [{"value", "HTTP"}], ["HTTP"]},
                {"option", [{"value", "S3"}], ["S3"]},
                {"option", [{"value", "SIRI"}], ["SIRI"]}
              ]}
           ] == view |> element("form select") |> render() |> Floki.parse_document!()

    assert ["aggregate-slug", "gtfs-rt-slug", "s3-slug", "siri-slug"] == slugs(view)

    form = view |> element("form")

    assert ["s3-slug"] == form |> search_by_type("S3") |> slugs()

    # Reset the form
    form |> search_by_type("")

    assert ["siri-slug"] == form |> search_by_value("siri") |> slugs()

    form |> search_by_type("SIRI")
    assert ["siri-slug"] == form |> search_by_value("siri") |> slugs()

    assert [] == form |> search_by_value("other") |> slugs()
    form |> search_by_type("")
    assert ["aggregate-slug", "gtfs-rt-slug", "s3-slug", "siri-slug"] == form |> search_by_value("slug") |> slugs()
  end

  defp search_by_value(%Phoenix.LiveViewTest.Element{} = el, value) do
    render_change(el, %{_target: ["search"], search: value})
  end

  defp search_by_type(%Phoenix.LiveViewTest.Element{} = el, value) do
    render_change(el, %{_target: ["type"], type: value})
  end

  defp slugs(%Phoenix.LiveViewTest.View{} = view), do: view |> render() |> slugs()

  defp slugs(content) when is_binary(content) do
    content
    |> Floki.parse_document!()
    |> Floki.find(~s|[data-name="unique-slug"]|)
    |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
  end
end
