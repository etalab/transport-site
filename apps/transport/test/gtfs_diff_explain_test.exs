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
        "initial_value" => "{\"stop_name\":\"Hôpital\"}",
        "new_value" => "{\"stop_name\":\"Hôpital Arnauzand\"}",
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
             {"stops.txt", "stop_name",
              "Le nom du stop_id 3000055 a été modifié. Nom initial : \"Hôpital\", Nouveau nom : \"Hôpital Arnauzand\""},
             {"stops.txt", "wheelchair_boarding",
              "Une information d'accessibilité wheelchair_boarding a été ajouté pour le stop_id 100, valeur initiale : \"0\", nouvelle valeur : \"1\""}
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
