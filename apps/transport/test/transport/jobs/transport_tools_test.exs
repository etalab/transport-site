defmodule TransportWeb.TransportToolsTest do
  use ExUnit.Case

  setup _ do
    Mox.stub_with(Transport.Rambo.Mock, Transport.Rambo)
    :ok
  end

  describe "we can launch tools from transport-tools folder" do
    # NOTE: the :transport_tools tag is just a quick fix to completely skip the tests outside CI, until
    # we implement a better version of this, allowing to skip by default yet allow local runs
    # with specific versions (either compiled locally, or Docker-pulled)
    # See https://github.com/etalab/transport-site/issues/1820
    @tag :transport_tools
    test "check the GeoJSON conversion binary is accessible" do
      {:error, msg} = Transport.GtfsToGeojsonConverter.convert("", "")

      # this is the error msg we would get if the binary file was not found
      assert msg != "rambo exited with 0"
    end

    @tag :transport_tools
    test "we can convert a gtfs to GeoJSON" do
      geojson_file = "test.geojson"
      :ok = Transport.GtfsToGeojsonConverter.convert("#{__DIR__}/../../fixture/files/gtfs.zip", geojson_file)
      assert geojson_file |> File.read!() |> String.contains?("FeatureCollection")
      File.rm!(geojson_file)
    end

    @tag :transport_tools
    test "we can convert a gtfs to NeTEx" do
      netex_dir = "test_netex"
      :ok = Transport.GtfsToNeTExConverter.convert("#{__DIR__}/../../fixture/files/gtfs.zip", netex_dir)
      assert File.dir?(netex_dir)
      File.rm_rf!(netex_dir)
    end
  end

  describe "Necessary command lines tools are installed on the machine" do
    @tag :transport_tools
    test "zip a simple folder" do
      zip_archive_path = [System.tmp_dir!(), "subfolder", "myzip.zip"] |> Path.join()
      content_folder_path = [System.tmp_dir!(), "subfolder", "folder_to_zip"] |> Path.join()

      content_folder_path
      |> File.mkdir_p!()

      File.write(Path.join([content_folder_path, "a_file"]), "the file content")

      # if the zip command is not available in the container, this will fail
      :ok = Transport.FolderZipper.zip(content_folder_path, zip_archive_path)

      # we check the content to be sure files are saved inside the zip
      # with path relative to "folder_to_zip", and we don't save absolute paths (ie /tmp/subfolder/folder_to_zip/a_file)
      zip_file = Unzip.LocalFile.open(zip_archive_path)
      {:ok, %Unzip{cd_list: %{"a_file" => _map}}} = Unzip.new(zip_file)
    end
  end
end
