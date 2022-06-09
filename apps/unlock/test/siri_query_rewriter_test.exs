defmodule Unlock.SIRI.QueryRewriterTest do
  use ExUnit.Case
  import SIRIQueries

  def parsed(xml) do
    {:ok, parsed_request} = Saxy.SimpleForm.parse_string(xml, cdata_as_characters: false)
    parsed_request
  end

  test "it generates correct XML for testing" do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    incoming_requestor_ref = "transport-data-gouv-fr"
    message_id = "Test::Message::#{Ecto.UUID.generate()}"
    stop_ref = "SomeStopRef"

    assert parsed(siri_query_from_builder(timestamp, incoming_requestor_ref, message_id, stop_ref)) ==
             filter_newlines_from_model(
               parsed(siri_query_from_template(timestamp, incoming_requestor_ref, message_id, stop_ref))
             )
  end

  test "dynamic requestor_ref modification and service verification" do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    incoming_requestor_ref = "transport-data-gouv-fr"
    message_id = "Test::Message::#{Ecto.UUID.generate()}"
    stop_ref = "SomeStopRef"

    xml = siri_query_from_builder(timestamp, incoming_requestor_ref, message_id, stop_ref)

    config = %{
      new_requestor_ref: "TARGET-REQUESTOR-REF"
    }

    {:ok, %{parsed_doc: parsed, incoming_requestor_ref: ^incoming_requestor_ref}} =
      Saxy.parse_string(xml, SIRI.Saxy.Handler, config)

    expected_output = siri_query_from_template(timestamp, "TARGET-REQUESTOR-REF", message_id, stop_ref)

    assert parsed |> filter_newlines_from_model ==
             expected_output |> parsed() |> filter_newlines_from_model

    {envelope, _, [{body, _, [{service, _, _}]}]} = parsed

    assert envelope |> XMLHelper.unnamespace() == "Envelope"
    assert body |> XMLHelper.unnamespace() == "Body"
    assert service |> XMLHelper.unnamespace() == "GetStopMonitoring"
  end
end
