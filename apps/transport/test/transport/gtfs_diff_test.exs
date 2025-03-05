defmodule Transport.GTFSDiffTest do
  use ExUnit.Case, async: true

  describe "GTFS Diff" do
    test "2 identical files" do
      unzip_1 = unzip("test/fixture/files/gtfs_diff/gtfs.zip")
      unzip_2 = unzip("test/fixture/files/gtfs_diff/gtfs.zip")

      for profile <- ["core", "full"] do
        diff = Transport.GTFSDiff.diff(unzip_1, unzip_2, profile)

        assert diff == []
      end
    end

    test "rows order is ignored" do
      unzip_1 = unzip("test/fixture/files/gtfs_diff/gtfs.zip")
      unzip_2 = unzip("test/fixture/files/gtfs_diff/gtfs_change_order.zip")

      for profile <- ["core", "full"] do
        diff = Transport.GTFSDiff.diff(unzip_1, unzip_2, profile)

        assert diff == []
      end
    end

    test "detect changes" do
      unzip_1 = unzip("test/fixture/files/gtfs_diff/gtfs.zip")
      unzip_2 = unzip("test/fixture/files/gtfs_diff/gtfs_modified_files.zip")

      for profile <- ["core", "full"] do
        diff = Transport.GTFSDiff.diff(unzip_1, unzip_2, profile)

        # calendar.txt is deleted
        # calendar_dates.txt is created with its content (one line)
        assert diff == [
                 %{
                   action: "add",
                   file: "calendar_dates.txt",
                   id: 0,
                   identifier: %{filename: "calendar_dates.txt"},
                   target: "file"
                 },
                 %{
                   action: "delete",
                   file: "calendar.txt",
                   id: 1,
                   identifier: %{filename: "calendar.txt"},
                   target: "file"
                 },
                 %{
                   action: "add",
                   file: "calendar_dates.txt",
                   id: 2,
                   identifier: %{column: "service_id"},
                   target: "column"
                 },
                 %{
                   action: "add",
                   file: "calendar_dates.txt",
                   id: 3,
                   identifier: %{"service_id" => "service2"},
                   new_value: %{"service_id" => "service2"},
                   target: "row"
                 }
               ]
      end
    end

    test "modified columns" do
      unzip_1 = unzip("test/fixture/files/gtfs_diff/gtfs.zip")
      unzip_2 = unzip("test/fixture/files/gtfs_diff/gtfs_modified_columns.zip")

      for profile <- ["core", "full"] do
        diff = Transport.GTFSDiff.diff(unzip_1, unzip_2, profile)

        # a column in calendar.txt is deleted
        # a column in agency.txt is added and 1 row has a value for the new column
        assert diff == [
                 %{
                   action: "add",
                   file: "agency.txt",
                   id: 0,
                   identifier: %{column: "agency_nickname"},
                   target: "column"
                 },
                 %{action: "delete", file: "calendar.txt", id: 1, identifier: %{column: "end_date"}, target: "column"},
                 %{
                   action: "update",
                   file: "agency.txt",
                   id: 2,
                   identifier: %{"agency_id" => "agency"},
                   initial_value: %{"agency_nickname" => ""},
                   new_value: %{"agency_nickname" => "little_agency"},
                   target: "row"
                 }
               ]
      end
    end

    test "modified rows" do
      unzip_1 = unzip("test/fixture/files/gtfs_diff/gtfs.zip")
      unzip_2 = unzip("test/fixture/files/gtfs_diff/gtfs_modified_rows.zip")

      for profile <- ["core", "full"] do
        diff = Transport.GTFSDiff.diff(unzip_1, unzip_2, profile)

        assert diff == [
                 %{
                   action: "add",
                   file: "routes.txt",
                   id: 0,
                   identifier: %{"route_id" => "1000"},
                   new_value: %{
                     "agency_id" => "agency",
                     "route_color" => "000000",
                     "route_desc" => "",
                     "route_id" => "1000",
                     "route_long_name" => "101",
                     "route_short_name" => "101",
                     "route_text_color" => "CCCCCC",
                     "route_type" => "3",
                     "route_url" => ""
                   },
                   target: "row"
                 },
                 %{action: "delete", file: "stops.txt", id: 1, identifier: %{"stop_id" => "near1"}, target: "row"},
                 %{
                   action: "update",
                   file: "stops.txt",
                   id: 2,
                   identifier: %{"stop_id" => "close2"},
                   initial_value: %{"stop_lon" => "2.449385"},
                   new_value: %{"stop_lon" => "2.443"},
                   target: "row"
                 }
               ]
      end
    end
  end

  describe "dump_diff" do
    test "empty diff, file is created" do
      tmp_path = System.tmp_dir!() |> Path.join(Ecto.UUID.generate())
      refute File.exists?(tmp_path)
      Transport.GTFSDiff.dump_diff([], tmp_path)
      assert File.exists?(tmp_path)

      assert [["id", "file", "action", "target", "identifier", "initial_value", "new_value", "note"]] ==
               read_csv(tmp_path)

      File.rm(tmp_path)
    end

    test "simple diff" do
      diff = [%{action: "delete", file: "stops.txt", id: 1, identifier: %{"stop_id" => "near1"}, target: "row"}]
      tmp_path = System.tmp_dir!() |> Path.join(Ecto.UUID.generate())
      refute File.exists?(tmp_path)
      Transport.GTFSDiff.dump_diff(diff, tmp_path)
      assert File.exists?(tmp_path)

      assert [
               ["id", "file", "action", "target", "identifier", "initial_value", "new_value", "note"],
               ["1", "stops.txt", "delete", "row", ~s({"stop_id":"near1"}), "", "", ""]
             ] == read_csv(tmp_path)

      File.rm(tmp_path)
    end
  end

  defp unzip(path) do
    zip_file = Unzip.LocalFile.open(path)
    {:ok, unzip} = Unzip.new(zip_file)
    unzip
  end

  defp read_csv(filepath) do
    filepath |> File.read!() |> NimbleCSV.RFC4180.parse_string(skip_headers: false)
  end
end
