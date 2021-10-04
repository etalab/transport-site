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
    path = Helpers.places_path(conn, :autocomplete, q: "chat")
    conn = conn |> get(path)
    r = conn |> json_response(200)

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

    [etag] = conn |> get_resp_header("etag")
    json_response(conn, 200)
    assert etag
    assert conn |> get_resp_header("cache-control") == ["max-age=60, public, must-revalidate"]

    # Passing the previous `ETag` value in a new HTTP request returns a 304
    conn |> recycle() |> put_req_header("if-none-match", etag) |> get(path) |> response(304)
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
