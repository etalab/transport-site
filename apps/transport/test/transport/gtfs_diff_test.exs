defmodule Transport.GTFSDiffTest do
  use ExUnit.Case, async: true

  defp unzip(path) do
    zip_file = Unzip.LocalFile.open(path)
    {:ok, unzip} = Unzip.new(zip_file)
    unzip
  end

  describe "GTFS Diff" do
    test "2 identical files" do
      unzip_1 = unzip("test/fixture/files/gtfs_diff/gtfs.zip")
      unzip_2 = unzip("test/fixture/files/gtfs_diff/gtfs.zip")

      diff = Transport.GTFSDiff.diff(unzip_1, unzip_2)

      assert diff == []
    end

    test "rows order is ignored" do
      unzip_1 = unzip("test/fixture/files/gtfs_diff/gtfs.zip")
      unzip_2 = unzip("test/fixture/files/gtfs_diff/gtfs_change_order.zip")

      diff = Transport.GTFSDiff.diff(unzip_1, unzip_2)

      assert diff == []
    end

    test "detect changes" do
      unzip_1 = unzip("test/fixture/files/gtfs_diff/gtfs.zip")
      unzip_2 = unzip("test/fixture/files/gtfs_diff/gtfs_modified_files.zip")

      diff = Transport.GTFSDiff.diff(unzip_1, unzip_2)

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

    test "modified columns" do
      unzip_1 = unzip("test/fixture/files/gtfs_diff/gtfs.zip")
      unzip_2 = unzip("test/fixture/files/gtfs_diff/gtfs_modified_columns.zip")

      diff = Transport.GTFSDiff.diff(unzip_1, unzip_2)

      # a column in calendar.txt is deleted
      # a column in agency.txt is added and 1 row has a value for the new column
      assert diff == [
               %{action: "add", file: "agency.txt", id: 0, identifier: %{column: "agency_nickname"}, target: "column"},
               %{action: "delete", file: "calendar.txt", id: 1, identifier: %{column: "end_date"}, target: "column"},
               %{
                 action: "update",
                 file: "agency.txt",
                 id: 2,
                 identifier: %{"agency_id" => "agency", "agency_name" => "BIBUS"},
                 initial_value: %{"agency_nickname" => ""},
                 new_value: %{"agency_nickname" => "little_agency"},
                 target: "row"
               }
             ]
    end

    test "modified rows" do
      unzip_1 = unzip("test/fixture/files/gtfs_diff/gtfs.zip")
      unzip_2 = unzip("test/fixture/files/gtfs_diff/gtfs_modified_rows.zip")

      diff = Transport.GTFSDiff.diff(unzip_1, unzip_2)

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
