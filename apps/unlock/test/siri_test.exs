defmodule Unlock.SIRITests do
  use ExUnit.Case
  import SIRIQueries

  doctest Unlock.SIRI
  doctest Unlock.SIRI.RequestorRefReplacer

  test "requestor ref can be changed on the fly" do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    incoming_requestor_ref = "transport-data-gouv-fr"
    message_id = "Test::Message::#{Ecto.UUID.generate()}"
    stop_ref = "SomeStopRef"

    # build some XML to simulate the input
    input_xml = siri_query_from_builder(timestamp, incoming_requestor_ref, message_id, stop_ref)

    # fake the parsing occurring in the controller
    parsed = Unlock.SIRI.parse_incoming(input_xml)

    output =
      RequestorRefReplacer.replace_requestor_ref(parsed, %{before: incoming_requestor_ref, after: "new-requestor-ref"})

    assert output ==
             siri_query_from_builder(timestamp, "new-requestor-ref", message_id, stop_ref)
             |> Unlock.SIRI.parse_incoming()
  end
end
