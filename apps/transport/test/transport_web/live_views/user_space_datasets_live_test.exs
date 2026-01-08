defmodule TransportWeb.Live.UserSpaceDatasetsLiveTest do
  use TransportWeb.ConnCase, async: true
  use Oban.Testing, repo: DB.Repo
  import Phoenix.LiveViewTest
  import DB.Factory

  doctest TransportWeb.Live.UserSpaceDatasetsLive, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "can filter datasets", %{conn: conn} do
    dijon_pt = insert(:dataset, type: "public-transit", custom_title: "Divia")
    dijon_vls = insert(:dataset, type: "vehicles-sharing", custom_title: "DiviaVélo")

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.UserSpaceDatasetsLive,
        session: %{
          "dataset_ids" => [dijon_pt.id, dijon_vls.id],
          "locale" => "fr",
          "csp_nonce_value" => Ecto.UUID.generate(),
          "mode" => :reuser
        }
      )

    assert [
             {"select", [{"id", "type"}, {"name", "type"}],
              [
                {"option", [{"selected", ""}, {"value", ""}], ["Tout"]},
                {"option", [{"value", "public-transit"}], ["Transport public collectif"]},
                {"option", [{"value", "vehicles-sharing"}], ["Véhicules en libre-service"]}
              ]}
           ] == view |> element("form select") |> render() |> Floki.parse_document!()

    refute has_element?(view, ".notification")

    assert ["Divia", "DiviaVélo"] == dataset_titles(view)

    form = view |> element("form")

    assert ["DiviaVélo"] == form |> search_by_value("velo") |> dataset_titles()
    assert ["DiviaVélo"] == form |> search_by_type("vehicles-sharing") |> dataset_titles()
    # Search "velo" + "public-transit" = no results
    assert [] == form |> search_by_type("public-transit") |> dataset_titles()
    assert has_element?(view, ".notification", "Pas de résultats")

    # Resetting the search value, only public-transit filter
    assert ["Divia"] == form |> search_by_value("") |> dataset_titles()
    # Resetting the type filter
    assert ["Divia", "DiviaVélo"] == form |> search_by_type("") |> dataset_titles()
  end

  test "does not display select by data type when there is a single type", %{conn: conn} do
    dijon_pt = insert(:dataset, type: "public-transit", custom_title: "Divia")

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.UserSpaceDatasetsLive,
        session: %{
          "dataset_ids" => [dijon_pt.id],
          "locale" => "fr",
          "csp_nonce_value" => Ecto.UUID.generate(),
          "mode" => :reuser
        }
      )

    refute has_element?(view, "form select")

    assert ["Divia"] == dataset_titles(view)

    form = view |> element("form")

    assert ["Divia"] == form |> search_by_value("via") |> dataset_titles()

    # No results
    assert [] == form |> search_by_value("nope") |> dataset_titles()
    assert has_element?(view, ".notification", "Pas de résultats")
  end

  defp search_by_value(%Phoenix.LiveViewTest.Element{} = el, value) do
    render_change(el, %{_target: ["search"], search: value})
  end

  defp search_by_type(%Phoenix.LiveViewTest.Element{} = el, value) do
    render_change(el, %{_target: ["type"], type: value})
  end

  defp dataset_titles(%Phoenix.LiveViewTest.View{} = view), do: view |> render() |> dataset_titles()

  defp dataset_titles(content) when is_binary(content) do
    content
    |> Floki.parse_document!()
    |> Floki.find(".dataset__title")
    |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
  end
end
