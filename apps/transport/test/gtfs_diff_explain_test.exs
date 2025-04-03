defmodule TransportWeb.GtfsDiffExplainTest do
  use ExUnit.Case, async: true
  doctest TransportWeb.GTFSDiffExplain, import: true
  alias TransportWeb.GTFSDiffExplain

  test "gtfs diff explanations" do
    diff = [
      %{
        "action" => "add",
        "file" => "agency.txt",
        "target" => "file"
      },
      %{
        "action" => "delete",
        "file" => "fares.txt",
        "target" => "file"
      },
      %{
        "action" => "update",
        "file" => "stops.txt",
        "identifier" => "{\"stop_id\":\"3000055\"}",
        "initial_value" => "{\"stop_name\":\"Hôpital\", \"stop_lat\":\"46.605513\", \"stop_lon\":\"0.275126\"}",
        "new_value" => "{\"stop_name\":\"Hôpital Arnauzand\", \"stop_lat\":\"46.605348\", \"stop_lon\":\"0.275881\"}",
        "target" => "row"
      },
      %{
        "action" => "update",
        "file" => "stops.txt",
        "identifier" => "{\"stop_id\":\"100\"}",
        "initial_value" => "{\"wheelchair_boarding\":\"0\"}",
        "new_value" => "{\"wheelchair_boarding\":\"1\"}",
        "target" => "row"
      }
    ]

    assert [
             %{
               file: "stops.txt",
               type: "stop_position",
               message: "La latitude de l’arrêt 3000055 a été modifiée",
               before: "46.605513",
               after: "46.605348",
               sort_key: "3000055-lat"
             },
             %{
               file: "stops.txt",
               type: "stop_position",
               message: "La longitude de l’arrêt 3000055 a été modifiée",
               before: "0.275126",
               after: "0.275881",
               sort_key: "3000055-lon"
             },
             %{
               file: "stops.txt",
               type: "stop_name",
               message: "L’arrêt 3000055 a été renommé",
               before: "Hôpital",
               after: "Hôpital Arnauzand",
               sort_key: "Hôpital"
             },
             %{
               file: "stops.txt",
               type: "wheelchair_boarding",
               message: "L’information d’accessibilité wheelchair_boarding a été modifiée pour l’arrêt 100",
               before: "0",
               after: "1",
               sort_key: "100"
             }
           ] == GTFSDiffExplain.diff_explanations(diff)
  end

  test "structural changes" do
    diff =
      [
        %{
          "action" => "delete",
          "file" => "agency.txt",
          "target" => "file"
        },
        %{
          "action" => "delete",
          "file" => "agency.txt",
          "target" => "column",
          "identifier" => "{\"column\": \"agency_id\"}"
        },
        %{
          "action" => "delete",
          "file" => "agency.txt",
          "target" => "column",
          "identifier" => "{\"column\": \"agency_name\"}"
        },
        %{
          "action" => "delete",
          "file" => "calendar.txt",
          "target" => "column",
          "identifier" => "{\"column\": \"start_date\"}"
        },
        %{
          "action" => "delete",
          "file" => "calendar.txt",
          "target" => "column",
          "identifier" => "{\"column\": \"end_date\"}"
        },
        %{
          "action" => "add",
          "file" => "calendar.txt",
          "target" => "column",
          "identifier" => "{\"column\": \"monday\"}"
        },
        %{
          "action" => "add",
          "file" => "stop_times.txt",
          "target" => "row"
        },
        %{
          "action" => "add",
          "file" => "trips.txt",
          "target" => "file"
        },
        %{
          "action" => "add",
          "file" => "trips.txt",
          "target" => "column",
          "identifier" => "{\"column\": \"route_id\"}"
        },
        %{
          "action" => "add",
          "file" => "trips.txt",
          "target" => "column",
          "identifier" => "{\"column\": \"service_id\"}"
        }
      ]

    assert %{
             "agency.txt" => [
               {:deleted_columns, ["agency_id", "agency_name"]},
               :deleted_file
             ],
             "calendar.txt" => [
               {:added_columns, ["monday"]},
               {:deleted_columns, ["end_date", "start_date"]}
             ],
             "trips.txt" => [
               {:added_columns, ["route_id", "service_id"]},
               :added_file
             ]
           } == GTFSDiffExplain.structural_changes(diff)
  end
end
