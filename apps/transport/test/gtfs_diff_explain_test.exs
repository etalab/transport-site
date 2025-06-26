defmodule TransportWeb.GtfsDiffExplainTest do
  use ExUnit.Case, async: true
  doctest TransportWeb.GTFSDiffExplain.Explanations, import: true
  doctest TransportWeb.GTFSDiffExplain.Summary, import: true
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
        "initial_value" => "{\"wheelchair_boarding\":\"0\", \"location_type\": \"0\"}",
        "new_value" => "{\"wheelchair_boarding\":\"1\", \"location_type\": \"1\"}",
        "target" => "row"
      },
      %{
        "action" => "update",
        "file" => "routes.txt",
        "identifier" => "{\"route_id\":\"146\"}",
        "initial_value" =>
          "{\"route_color\":\"5C2483\", \"route_text_color\":\"FFFFFF\", \"route_short_name\":\"30\", \"route_long_name\":\"Migné Rochereaux-Laborit/Mignaloux\", \"route_type\":\"0\"}",
        "new_value" =>
          "{\"route_color\":\"0000B0\", \"route_text_color\":\"000000\", \"route_short_name\":\"TER\", \"route_long_name\":\"Migné Rochereaux-Laborit / Mignaloux\", \"route_type\":\"1\"}",
        "target" => "row"
      },
      %{
        "action" => "update",
        "file" => "routes.txt",
        "identifier" => "{\"route_id\":\"147\"}",
        "initial_value" => "{\"route_color\":\"5c2483\", \"route_text_color\":\"ffffff\"}",
        "new_value" => "{\"route_color\":\"5C2483\", \"route_text_color\":\"FFFFFF\"}",
        "target" => "row"
      },
      %{
        "action" => "update",
        "file" => "agency.txt",
        "identifier" => "{\"agency_id\":\"1\"}",
        "initial_value" => "{\"agency_url\":\"http://localhost/foo\"}",
        "new_value" => "{\"agency_url\":\"http://localhost/bar\"}",
        "target" => "row"
      },
      %{
        "action" => "update",
        "file" => "trips.txt",
        "identifier" => "{\"trip_id\":\"1\"}",
        "initial_value" => "{\"trip_headsign\":\"Foo\"}",
        "new_value" => "{\"trip_headsign\":\"Bar\"}",
        "target" => "row"
      }
    ]

    assert MapSet.new([
             %{
               file: "stops.txt",
               type: "stop_position",
               message: "L’arrêt 3000055 a été déplacé de 61m",
               before: "(46.605513, 0.275126)",
               after: "(46.605348, 0.275881)",
               sort_key: -61
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
             },
             %{
               file: "routes.txt",
               type: "route_text_color",
               message: "La couleur de texte de la route 146 a été modifiée",
               before: "#FFFFFF",
               after: "#000000",
               sort_key: "146"
             },
             %{
               file: "routes.txt",
               type: "route_color",
               message: "La couleur de la route 146 a été modifiée",
               before: "#5C2483",
               after: "#0000B0",
               sort_key: "146"
             },
             %{
               file: "routes.txt",
               type: "route_long_name",
               message: "Le nom long de la route 146 a été modifié",
               before: "Migné Rochereaux-Laborit/Mignaloux",
               after: "Migné Rochereaux-Laborit / Mignaloux",
               sort_key: "146"
             },
             %{
               file: "routes.txt",
               type: "route_short_name",
               message: "Le nom court de la route 146 a été modifié",
               before: "30",
               after: "TER",
               sort_key: "146"
             },
             %{
               file: "routes.txt",
               type: "route_type",
               message: "Le type de la route 146 a été modifié",
               before: "0",
               after: "1",
               sort_key: "146"
             },
             %{
               file: "stops.txt",
               type: "location_type",
               message: "Le type de lieu pour l’arrêt 100 a été modifié",
               before: "0",
               after: "1",
               sort_key: "100"
             },
             %{
               file: "agency.txt",
               type: "agency_url",
               message: "L’URL de l’entité 1 a été modifiée",
               before: "http://localhost/foo",
               after: "http://localhost/bar",
               sort_key: "1"
             },
             %{
               file: "trips.txt",
               type: "trip_headsign",
               message: "Le panneau de destination du trajet 1 a été modifié",
               before: "Foo",
               after: "Bar",
               sort_key: "1"
             }
           ]) == GTFSDiffExplain.diff_explanations(diff) |> MapSet.new()
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
