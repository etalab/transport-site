defmodule TransportWeb.API.PlacesControllerTest do
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  use TransportWeb.ConnCase, async: false
  alias TransportWeb.API.Router.Helpers
  alias DB.{AOM, Commune, Dataset, Region, Repo}

  defp cleanup(value) do
    # we cannot compare the urls as they can contain internal unstable db id
    # so we strip the id, the last fragment of the url
    Regex.replace(~r/([[:alnum:]]+$)/, value, ":id")
  end

  # to be able to compare the result in a stable way, we sort and clean them
  defp sort_and_clean(res),
    do:
      res
      |> Enum.sort()
      |> Enum.map(&Map.update!(&1, "url", fn v -> cleanup(v) end))

  test "Search a place", %{conn: conn} do
    r =
      conn
      |> get(Helpers.places_path(conn, :autocomplete, q: "chat"))
      |> json_response(200)

    assert sort_and_clean(r) ==
             Enum.sort([
               %{
                 "name" => "Châteauroux (36044)",
                 "type" => "commune",
                 "url" => "/datasets/commune/:id"
               },
               %{
                 "name" => "Châteauroux",
                 "type" => "aom",
                 "url" => "/datasets/aom/:id"
               }
             ])
  end

  test "Search a place with accent", %{conn: conn} do
    r =
      conn
      |> get(Helpers.places_path(conn, :autocomplete, q: "cha"))
      |> json_response(200)

    assert sort_and_clean(r) ==
             Enum.sort([
               %{
                 "name" => "Châteauroux (36044)",
                 "type" => "commune",
                 "url" => "/datasets/commune/:id"
               },
               %{
                 "name" => "Châteauroux",
                 "type" => "aom",
                 "url" => "/datasets/aom/:id"
               },
               %{
                 "name" => "Chas (63096)",
                 "type" => "commune",
                 "url" => "/datasets/commune/:id"
               }
             ])
  end

  test "Search a place with multiple word", %{conn: conn} do
    r =
      conn
      |> get(Helpers.places_path(conn, :autocomplete, q: "ile de fr"))
      |> json_response(200)

    assert sort_and_clean(r) ==
             Enum.sort([
               %{
                 "name" => "Île-de-France Mobilités",
                 "type" => "aom",
                 "url" => "/datasets/aom/:id"
               },
               %{
                 "name" => "Île-de-France",
                 "type" => "region",
                 "url" => "/datasets/region/:id"
               }
             ])
  end

  test "Search a unknown place", %{conn: conn} do
    r =
      conn
      |> get(Helpers.places_path(conn, :autocomplete, q: "pouet"))
      |> json_response(200)

    assert sort_and_clean(r) == []
  end
end
