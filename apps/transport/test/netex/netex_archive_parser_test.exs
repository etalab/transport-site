defmodule Transport.NeTEx.ArchiveParserTest do
  use ExUnit.Case, async: true

  defmodule ZipCreator do
    @moduledoc """
    A light wrapper around OTP `:zip` features. Does not support streaming here,
    but massages the string <-> charlist differences.
    """
    @spec create!(String.t(), [{String.t(), binary()}]) :: no_return()
    def create!(zip_filename, file_data) do
      {:ok, ^zip_filename} =
        :zip.create(
          zip_filename,
          file_data
          |> Enum.map(fn {name, content} -> {name |> to_charlist(), content} end)
        )
    end
  end

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
    ZipCreator.create!(tmp_file, [{"arrets.xml", some_netex_content()}])

    # given a zip netex archive containing 1 file, I want the output I expected
    [{"arrets.xml", data}] = Transport.NeTEx.read_all_stop_places(tmp_file)

    assert data ==
             {:ok,
              [
                %{id: "FR:HELLO:POYARTIN:001", latitude: 43.669, longitude: -0.919, name: "Poyartin"}
              ]}

    # given a zip netex archive containing 1 file, I want the output I expected
    [{"arrets.xml", data}] = Transport.NeTEx.read_all_stop_places!(tmp_file)

    assert data == [
             %{id: "FR:HELLO:POYARTIN:001", latitude: 43.669, longitude: -0.919, name: "Poyartin"}
           ]
  end
end
