defmodule TransportWeb.API.PlacesControllerTest do
  use TransportWeb.ConnCase, async: true
  alias TransportWeb.API.Router.Helpers
  import OpenApiSpex.TestAssertions
  import DB.Factory

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    insert(:administrative_division, nom: "Châteauroux", insee: "36044", type: :commune, type_insee: "commune_36044")
    insert(:administrative_division, nom: "Châteauroux", insee: "1", type: :epci, type_insee: "epci_1")
    insert(:administrative_division, nom: "Île-de-France", insee: "2", type: :region, type_insee: "region_2")
    insert(:administrative_division, nom: "Île-de-France Mobilités", insee: "3", type: :epci, type_insee: "epci_3")
    insert(:administrative_division, nom: "Chas", insee: "63096", type: :commune, type_insee: "commune_63096")
    :ok
  end

  defp cleanup(value) do
    # we cannot compare the urls as they can contain internal unstable db id
    # so we strip the id, the last fragment of the url
    Regex.replace(~r/([[:alnum:]]+$)/, value, ":id")
  end

  defp clean_urls(res),
    do: Enum.map(res, &Map.update!(&1, "url", fn v -> cleanup(v) end))

  test "Search a place", %{conn: conn} do
    path = Helpers.places_path(conn, :autocomplete, q: "chat")
    conn = conn |> get(path)
    r = conn |> json_response(200)

    assert clean_urls(r) ==
             [
               %{
                 "name" => "Châteauroux",
                 "type" => "epci",
                 "url" => "/datasets/epci/:id"
               },
               %{
                 "name" => "Châteauroux (36044)",
                 "type" => "commune",
                 "url" => "/datasets/commune/:id"
               }
             ]

    [etag] = conn |> get_resp_header("etag")
    json = json_response(conn, 200)
    assert etag
    assert conn |> get_resp_header("cache-control") == ["max-age=60, public, must-revalidate"]

    # Passing the previous `ETag` value in a new HTTP request returns a 304
    conn |> recycle() |> put_req_header("if-none-match", etag) |> get(path) |> response(304)

    assert_response_schema(json, "AutocompleteResponse", TransportWeb.API.Spec.spec())
  end

  test "Search a place with accent", %{conn: conn} do
    json =
      conn
      |> get(Helpers.places_path(conn, :autocomplete, q: "cha"))
      |> json_response(200)

    assert clean_urls(json) ==
             [
               %{
                 "name" => "Châteauroux",
                 "type" => "epci",
                 "url" => "/datasets/epci/:id"
               },
               %{
                 "name" => "Chas (63096)",
                 "type" => "commune",
                 "url" => "/datasets/commune/:id"
               },
               %{
                 "name" => "Châteauroux (36044)",
                 "type" => "commune",
                 "url" => "/datasets/commune/:id"
               }
             ]

    assert_response_schema(json, "AutocompleteResponse", TransportWeb.API.Spec.spec())
  end

  test "Search a place with multiple words", %{conn: conn} do
    json =
      conn
      |> get(Helpers.places_path(conn, :autocomplete, q: "ile de fr"))
      |> json_response(200)

    assert clean_urls(json) ==
             [
               %{
                 "name" => "Île-de-France",
                 "type" => "region",
                 "url" => "/datasets/region/:id"
               },
               %{
                 "name" => "Île-de-France Mobilités",
                 "type" => "epci",
                 "url" => "/datasets/epci/:id"
               }
             ]

    assert_response_schema(json, "AutocompleteResponse", TransportWeb.API.Spec.spec())
  end

  test "Search an unknown place", %{conn: conn} do
    json =
      conn
      |> get(Helpers.places_path(conn, :autocomplete, q: "pouet"))
      |> json_response(200)

    assert clean_urls(json) == []

    assert_response_schema(json, "AutocompleteResponse", TransportWeb.API.Spec.spec())
  end
end
