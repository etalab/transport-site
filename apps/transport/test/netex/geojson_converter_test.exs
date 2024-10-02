defmodule Transport.NeTEx.GeoJSONConverterTest do
  use ExUnit.Case, async: true

  # not fully correct XML, but close enough for what we want to test
  def some_netex_content do
    """
      <GeneralFrame>
        <members>
          <StopPlace id="FR:HELLO:POYARTIN:001">
            <Name>Poyartin</Name>
            <Centroid>
              <Location>
                <Latitude>43.6690</Latitude>
                <Longitude>-0.9190</Longitude>
              </Location>
            </Centroid>
          </StopPlace>
          <StopPlace id="FR:HELLO:DAX:001">
            <Name>Dax</Name>
            <Centroid>
              <Location>
                <Latitude>43.7154</Latitude>
                <Longitude>-1.0530</Longitude>
              </Location>
            </Centroid>
          </StopPlace>
        </members>
      </GeneralFrame>
    """
  end

  test "valid JSON from valid NeTEx" do
    tmp_file = System.tmp_dir!() |> Path.join("temp-netex-#{Ecto.UUID.generate()}.zip")

    netex_files = [
      {"arrets_1.xml", some_netex_content()},
      {"arrets_2.xml", some_netex_content()}
    ]

    Transport.ZipCreator.create!(tmp_file, netex_files)

    result = Transport.NeTEx.GeoJSONConverter.convert(tmp_file)

    assert {:ok,
            %{
              type: "FeatureCollection",
              features: [
                %{
                  type: "Feature",
                  geometry: %{type: "Point", coordinates: [-0.919, 43.669]},
                  properties: %{name: "Poyartin"}
                },
                %{
                  type: "Feature",
                  geometry: %{type: "Point", coordinates: [-1.053, 43.7154]},
                  properties: %{name: "Dax"}
                },
                %{
                  type: "Feature",
                  geometry: %{type: "Point", coordinates: [-0.919, 43.669]},
                  properties: %{name: "Poyartin"}
                },
                %{
                  type: "Feature",
                  geometry: %{type: "Point", coordinates: [-1.053, 43.7154]},
                  properties: %{name: "Dax"}
                }
              ]
            }} = Jason.decode(result, keys: :atoms)
  end
end
