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
             {"agency.txt", "Un fichier \"agency.txt\" a été ajouté"},
             {"fares.txt", "Le fichier \"fares.txt\" a été supprimé"},
             {"stops.txt",
              "Le nom du stop_id 3000055 a été modifié. Nom initial : \"Hôpital\", Nouveau nom : \"Hôpital Arnauzand\""},
             {"stops.txt",
              "Une information d'accessibilité wheelchair_boarding a été ajouté pour le stop_id 100, valeur initiale : \"0\", nouvelle valeur : \"1\""}
           ] == GTFSDiffExplain.diff_explanations(diff)
  end
end
