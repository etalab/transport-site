defmodule Transport.NeTEx.ArchiveParserTest do
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
        </members>
      </GeneralFrame>
    """
  end

  test "traverse the archive and return relevant content" do
    tmp_file = System.tmp_dir!() |> Path.join("temp-netex-#{Ecto.UUID.generate()}.zip")
    Transport.ZipCreator.create!(tmp_file, [{"arrets.xml", some_netex_content()}])

    # given a zip netex archive containing 1 file, I want the output I expected
    [{"arrets.xml", data}] = Transport.NeTEx.read_all_stop_places(tmp_file)

    assert data == [
             %{id: "FR:HELLO:POYARTIN:001", latitude: 43.669, longitude: -0.919, name: "Poyartin"}
           ]
  end
end
