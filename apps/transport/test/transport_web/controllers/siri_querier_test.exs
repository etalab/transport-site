defmodule TransportWeb.SIRIQuerierLiveTest do
  use TransportWeb.ConnCase, async: true
  use Oban.Testing, repo: DB.Repo
  import Mox
  import Phoenix.LiveViewTest
  alias TransportWeb.Live.SIRIQuerierLive

  setup :verify_on_exit!

  test "renders form", %{conn: conn} do
    conn |> get(live_path(conn, SIRIQuerierLive)) |> html_response(200)
  end

  test "uses query params to set input values", %{conn: conn} do
    {:ok, view, _html} =
      conn
      |> get(
        live_path(conn, SIRIQuerierLive,
          endpoint_url: endpoint_url = Ecto.UUID.generate(),
          requestor_ref: requestor_ref = Ecto.UUID.generate()
        )
      )
      |> live()

    assert view |> element(~s{[name="config[endpoint_url]"}) |> render() =~ ~s(value="#{endpoint_url}")
    assert view |> element(~s{[name="config[requestor_ref]"}) |> render() =~ ~s(value="#{requestor_ref}")
  end

  test "clicking on generate and then execute", %{conn: conn} do
    {:ok, view, _html} = conn |> get(live_path(conn, SIRIQuerierLive)) |> live()

    view
    |> render_change("change_form", %{
      "config" => %{
        "endpoint_url" => endpoint_url = "https://example.com",
        "requestor_ref" => requestor_ref = Ecto.UUID.generate(),
        "query_template" => "CheckStatus"
      }
    })

    assert_patched(view, live_path(conn, SIRIQuerierLive, endpoint_url: endpoint_url))

    # Form's submit is mapped to the "generate_query" event
    assert view |> element("#siri_querier") |> render() =~ ~s{phx-submit="generate_query"}
    assert view |> has_element?(~s{button[type="submit"})
    refute view |> has_element?(~s{button[phx-click="execute_query"})

    # Clicking on "Generate" makes the "Execute" button show up
    view |> render_change("generate_query")
    assert view |> has_element?(~s{button[phx-click="execute_query"})

    # SIRI query is displayed
    assert view |> has_element?("#query_code_wrapper")
    refute view |> has_element?("#response_code_wrapper")

    assert view |> element("#siri_query_wrapper") |> render() =~
             "<siri:RequestorRef>#{requestor_ref}</siri:RequestorRef>"
             |> Phoenix.HTML.html_escape()
             |> Phoenix.HTML.safe_to_string()

    assert view |> element("#siri_query_wrapper") |> render() =~ "sw:CheckStatus"

    # Clicking on execute
    Transport.HTTPoison.Mock
    |> expect(:post!, fn ^endpoint_url, _body ->
      %HTTPoison.Response{
        status_code: 200,
        body: """
        <?xml version="1.0" encoding="utf-8"?>
        <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/">
          <S:Body>
            <sw:CheckStatusResponse xmlns:sw="http://wsdl.siri.org.uk" xmlns:siri="http://www.siri.org.uk/siri">
              <CheckStatusAnswerInfo>
                <siri:ResponseTimestamp>2022-10-24T14:05:22.471+02:00</siri:ResponseTimestamp>
                <siri:ProducerRef>Ara</siri:ProducerRef>
                <siri:ResponseMessageIdentifier>47ddcbb9-2b28-4c53-8f32-a8599a667d9e</siri:ResponseMessageIdentifier>
                <siri:RequestMessageRef>Test::Message::d55c816c-0514-4f28-84ff-f3ec9a13e042</siri:RequestMessageRef>
              </CheckStatusAnswerInfo>
              <Answer>
                <siri:Status>true</siri:Status>
                <siri:ServiceStartedTime>2022-10-24T04:00:00.543+02:00</siri:ServiceStartedTime>
              </Answer>
              <AnswerExtension/>
            </sw:CheckStatusResponse>
          </S:Body>
        </S:Envelope>
        """,
        headers: [{"Content-Type", "text/xml"}]
      }
    end)

    view |> element(~s{button[phx-click="execute_query"}) |> render_click()
    assert view |> has_element?("#response_code_wrapper")
    assert view |> render() =~ "HTTP status 200"
    assert view |> render() =~ "Content-Type: text/xml"
    assert view |> element("#siri_response_wrapper") |> render() =~ "CheckStatusAnswerInfo"
  end
end
