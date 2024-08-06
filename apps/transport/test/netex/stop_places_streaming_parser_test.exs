defmodule Transport.NeTEx.StopPlacesStreamingParserTest do
  use ExUnit.Case, async: true

  alias Transport.NeTEx.StopPlacesStreamingParser

  def get_stop_places(xml) do
    state = %{
      current_stop_place: nil,
      capture: false,
      current_tree: [],
      stop_places: [],
      callback: fn state ->
        state |> update_in([:stop_places], &(&1 ++ [state.current_stop_place]))
      end
    }

    {:ok, final_state} = Saxy.parse_string(xml, StopPlacesStreamingParser, state)
    final_state.stop_places
  end

  test "parses a simple NeTEx StopPlace with Name and Coordinates" do
    xml = """
    <StopPlace id="FR:HELLO:POYARTIN:001">
      <Name>Poyartin</Name>
      <Centroid>
        <Location>
          <Latitude>43.6690</Latitude>
          <Longitude>-0.9190</Longitude>
        </Location>
      </Centroid>
    </StopPlace>
    """

    assert get_stop_places(xml) == [
             %{
               id: "FR:HELLO:POYARTIN:001",
               name: "Poyartin",
               latitude: 43.6690,
               longitude: -0.9190
             }
           ]
  end

  test "parses multiple stop places, including ones with limited data" do
    xml = """
    <SomeParentNode>
      <StopPlace id="FR:HELLO:AUBIERE:001">
        <Name>Aubière</Name>
      </StopPlace>
      <StopPlace id="FR:HELLO:AUBIERE:001:A">
        <Name>Aubière (A)</Name>
        <ParentSiteRef ref="FR:HELLO:AUBIERE:001"/>
        <Centroid>
          <Location>
            <Latitude>45.7594</Latitude>
            <Longitude>3.1130</Longitude>
          </Location>
        </Centroid>
      </StopPlace>
    </SomeParentNode>
    """

    assert get_stop_places(xml) == [
             %{
               id: "FR:HELLO:AUBIERE:001",
               name: "Aubière"
             },
             %{
               id: "FR:HELLO:AUBIERE:001:A",
               name: "Aubière (A)",
               latitude: 45.7594,
               longitude: 3.1130
             }
           ]
  end
end
