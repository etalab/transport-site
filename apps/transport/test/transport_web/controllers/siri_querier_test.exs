defmodule TransportWeb.SIRIQuerierLiveTest do
  use TransportWeb.ConnCase, async: true
  use Oban.Testing, repo: DB.Repo
  import Mox
  import Phoenix.LiveViewTest
  alias TransportWeb.Live.SIRIQuerierLive

  setup do
    # Ensure the query generated properly marshalls the input and propagate them
    Mox.stub_with(Transport.SIRIQueryGenerator.Mock, Transport.SIRIQueryGenerator)

    :ok
  end

  setup :verify_on_exit!

  test "renders form", %{conn: conn} do
    conn |> get(live_path(conn, SIRIQuerierLive)) |> html_response(200)
  end

  test "uses query params to set input values when provided", %{conn: conn} do
    {:ok, view, _html} =
      conn
      |> get(
        live_path(conn, SIRIQuerierLive,
          endpoint_url: endpoint_url = Ecto.UUID.generate(),
          requestor_ref: requestor_ref = Ecto.UUID.generate(),
          query_template: query_template = "LinesDiscovery"
        )
      )
      |> live()

    assert view |> element(~s{[name="config[endpoint_url]"]}) |> render() =~ ~s(value="#{endpoint_url}")
    assert view |> element(~s{[name="config[requestor_ref]"]}) |> render() =~ ~s(value="#{requestor_ref}")
    assert view |> element(~s{[name="config[query_template]"]}) |> render() =~ ~s(value="#{query_template}")
  end

  test "clicking on generate and then execute", %{conn: conn} do
    {:ok, view, _html} = conn |> get(live_path(conn, SIRIQuerierLive)) |> live()

    view
    |> render_change("change_form", %{
      "config" => %{
        "endpoint_url" => endpoint_url = "https://example.com",
        "requestor_ref" => requestor_ref = Ecto.UUID.generate(),
        "query_template" => query_template = "CheckStatus"
      }
    })

    assert_patched(
      view,
      live_path(conn, SIRIQuerierLive,
        endpoint_url: endpoint_url,
        requestor_ref: requestor_ref,
        query_template: query_template
      )
    )

    # Form has the "Generate" button but not the "Execute" one
    assert view |> has_element?(~s{button[phx-click="generate_query"]})
    refute view |> has_element?(~s{button[phx-click="execute_query"]})

    # Clicking on "Generate" makes the "Execute" button show up
    view |> element(~s{button[phx-click="generate_query"]}) |> render_click()
    assert view |> has_element?(~s{button[phx-click="execute_query"]})

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
    |> expect(:post, fn ^endpoint_url, _body, [{"content-type", "text/xml"}], [recv_timeout: _] ->
      {:ok,
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
       }}
    end)

    view |> element(~s{button[phx-click="execute_query"]}) |> render_click()
    assert view |> has_element?("#response_code_wrapper")
    assert view |> render() =~ "HTTP status 200"
    assert view |> render() =~ "Content-Type: text/xml"
    assert view |> element("#siri_response_wrapper") |> render() =~ "CheckStatusAnswerInfo"

    # With a server error
    Transport.HTTPoison.Mock
    |> expect(:post, fn ^endpoint_url, _body, [{"content-type", "text/xml"}], [recv_timeout: _] ->
      {:error, %HTTPoison.Error{reason: "Got an error"}}
    end)

    view |> element(~s{button[phx-click="execute_query"]}) |> render_click()
    refute view |> has_element?("#response_code_wrapper")
    assert view |> has_element?("#siri_response_error")
    assert view |> element("#siri_response_error") |> render() =~ "Got an error"

    # re-encodes a latin1 body to UTF-8
    # Express `£éduff` in latin1 as bytes first
    latin1 = <<163, 233, 100, 117, 102, 102>>
    expected_utf8_conversion = "£éduff"

    Transport.HTTPoison.Mock
    |> expect(:post, fn ^endpoint_url, _body, [{"content-type", "text/xml"}], [recv_timeout: _] ->
      {:ok,
       %HTTPoison.Response{
         body: latin1,
         headers: [{"Content-Type", "text/plain;charset=ISO-8859-1"}],
         status_code: 200
       }}
    end)

    view |> element(~s{button[phx-click="execute_query"]}) |> render_click()

    assert view |> element("#siri_response_wrapper") |> render() =~
             ~s(<input type="hidden" value="#{expected_utf8_conversion}" data-code="response_code_id")

    refute view |> has_element?("#siri_response_error")
  end

  test "choosing GetEstimatedTimetable allows to input line references", %{conn: conn} do
    {:ok, view, _html} =
      conn
      |> get(live_path(conn, SIRIQuerierLive))
      |> live()

    # By default, we must be on CheckStatus
    assert view
           |> element("select option:checked")
           |> render() =~ "CheckStatus"

    # And the user cannot input line references
    refute view |> has_element?("#siri_querier_line_refs")

    # Select GetEstimatedTimetable
    assert view
           |> element("form")
           |> render_change(%{
             config: %{
               "requestor_ref" => "test-ref",
               "query_template" => "GetEstimatedTimetable"
             }
           })

    # Should be selected
    assert view
           |> element("select option:checked")
           |> render() =~ "GetEstimatedTimetable"

    # The user should be offered a way to type line references
    assert view |> has_element?("#siri_querier_line_refs")

    # Simulate user typing in
    view
    |> form("#siri_querier")
    |> render_change(%{config: %{"line_refs" => " VILX, 101"}})

    xml_query = "<payload></payload>"

    Transport.SIRIQueryGenerator.Mock
    |> expect(:generate_query, fn params ->
      # comma-separated split, trimmed
      assert params[:line_refs] == ["VILX", "101"]
      assert params[:template] == "GetEstimatedTimetable"
      assert params[:requestor_ref] == "test-ref"
      assert params[:message_id] =~ "Test::Message"

      xml_query
    end)

    # Clicking on "Generate" makes the "Execute" button show up
    view |> element(~s{button[phx-click="generate_query"]}) |> render_click()

    # The payload should come back
    assert view
           |> element("#siri_query_wrapper")
           |> render()
           |> Floki.parse_document!()
           |> Floki.attribute("value") == [xml_query]

    assert_patched(
      view,
      live_path(conn, SIRIQuerierLive,
        requestor_ref: "test-ref",
        query_template: "GetEstimatedTimetable",
        line_refs: " VILX, 101"
      )
    )
  end

  test "choosing GetStopMonitoring allows to input stop reference", %{conn: conn} do
    {:ok, view, _html} =
      conn
      |> get(live_path(conn, SIRIQuerierLive))
      |> live()

    # And the user cannot input stop reference
    refute view |> has_element?("#siri_querier_stop_ref")

    # Select GetStopMonitoring
    assert view
           |> element("form")
           |> render_change(%{
             config: %{
               "requestor_ref" => "test-ref",
               "query_template" => "GetStopMonitoring"
             }
           })

    # Should be selected
    assert view
           |> element("select option:checked")
           |> render() =~ "GetStopMonitoring"

    # The user should be offered a way to type stop reference
    assert view |> has_element?("#siri_querier_stop_ref")

    # Simulate user typing in
    view
    |> form("#siri_querier")
    |> render_change(%{config: %{"stop_ref" => " Test:StopPoint "}})

    xml_query = "<payload></payload>"

    Transport.SIRIQueryGenerator.Mock
    |> expect(:generate_query, fn params ->
      # trimmed
      assert params[:stop_ref] == "Test:StopPoint"
      assert params[:template] == "GetStopMonitoring"
      assert params[:requestor_ref] == "test-ref"
      assert params[:message_id] =~ "Test::Message"

      xml_query
    end)

    # Clicking on "Generate" makes the "Execute" button show up
    view |> element(~s{button[phx-click="generate_query"]}) |> render_click()

    # The payload should come back
    assert view
           |> element("#siri_query_wrapper")
           |> render()
           |> Floki.parse_document!()
           |> Floki.attribute("value") == [xml_query]

    assert_patched(
      view,
      live_path(conn, SIRIQuerierLive,
        requestor_ref: "test-ref",
        query_template: "GetStopMonitoring",
        stop_ref: " Test:StopPoint "
      )
    )
  end
end
