defmodule Transport.GtfsRtParserTest do
  use ExUnit.Case, async: true

  @sample_file "#{__DIR__}/../fixture/files/bibus-brest-gtfs-rt-alerts.pb"

  test "parses a sample GTFS-RT file" do
    body = File.read!(@sample_file)
    data = TransitRealtime.FeedMessage.decode(body)

    # demo for access to header properties
    :FULL_DATASET = data.header.incrementality

    # the entity has cardinality N, so is an array
    message = data.entity |> List.first()

    assert message.id == "2ea09850-74d9-4db7-a537-d97d821956e8"
    assert message.vehicle == nil
    assert message.trip_update == nil
    assert message.alert.cause == :CONSTRUCTION
    assert message.alert.description_text.translation |> List.first() |> Map.get(:text) =~ ~r/Prolongation des travaux/
  end
end
