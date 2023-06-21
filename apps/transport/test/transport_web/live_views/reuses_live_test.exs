defmodule Transport.TransportWeb.ReusesLiveTest do
  use TransportWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import DB.Factory
  import Mox

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "render some reuses", %{conn: conn} do
    insert(:dataset, datagouv_id: datagouv_id = Ecto.UUID.generate())

    Datagouvfr.Client.Reuses.Mock
    |> expect(:get, 1, fn %{datagouv_id: ^datagouv_id} ->
      {:ok, reuses()}
    end)

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.ReusesLive,
        session: %{
          "dataset_datagouv_id" => datagouv_id,
          "locale" => "fr"
        }
      )

    assert render(view) =~ "Bornes et station de recharge pour véhicules électriques"
  end

  test "renders even if data.gouv is down", %{conn: conn} do
    insert(:dataset, datagouv_id: datagouv_id = Ecto.UUID.generate())

    # in case of request failure, the function returns an empty list.
    Datagouvfr.Client.Reuses.Mock |> expect(:get, 1, fn %{datagouv_id: ^datagouv_id} -> {:error, "not working"} end)

    assert {:ok, view, _html} =
             live_isolated(conn, TransportWeb.ReusesLive,
               session: %{
                 "dataset_datagouv_id" => datagouv_id,
                 "locale" => "fr"
               }
             )

    # we render the view to make sure the async call to data.gouv is done
    assert render(view) =~ ""
  end

  test "the counter reacts to broadcasted messages", %{conn: conn} do
    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.CountReusesLive,
        session: %{
          "dataset_datagouv_id" => datagouv_id = Ecto.UUID.generate()
        }
      )

    refute render(view) =~ "Réutilisations"

    Phoenix.PubSub.broadcast(
      TransportWeb.PubSub,
      "dataset_reuses_count:bad_dataset_id",
      {:count, 10}
    )

    refute render(view) =~ "Réutilisations"

    Phoenix.PubSub.broadcast(
      TransportWeb.PubSub,
      "dataset_reuses_count:#{datagouv_id}",
      {:count, 10}
    )

    assert render(view) =~ "Réutilisations"
  end

  defp reuses do
    [
      %{
        "badges" => [],
        "created_at" => "2021-08-10T15:29:09.918000+00:00",
        "datasets" => [
          %{
            "page" =>
              "https://demo.data.gouv.fr/fr/datasets/fichier-consolide-des-bornes-de-recharge-pour-vehicules-electriques/",
            "title" => "Fichier consolidé des Bornes de Recharge pour Véhicules Électriques",
            "uri" =>
              "https://demo.data.gouv.fr/api/1/datasets/fichier-consolide-des-bornes-de-recharge-pour-vehicules-electriques/"
          }
        ],
        "deleted" => nil,
        "description" => "Bornes et station de recharge pour véhicules électriques.",
        "featured" => nil,
        "id" => "61127f25f52dc5cf5c3e78ca",
        "image" => "https://demo-static.data.gouv.fr/images/6a/9a7d3e6c0a4254b0e0b444d8ae0706.jpg",
        "image_thumbnail" => "https://demo-static.data.gouv.fr/images/6a/9a7d3e6c0a4254b0e0b444d8ae0706-500.jpg",
        "last_modified" => "2022-05-23T20:59:34.578000+00:00",
        "metrics" => %{
          "datasets" => 1,
          "discussions" => 1,
          "followers" => 0,
          "views" => 3
        },
        "organization" => %{
          "acronym" => "Citelec",
          "badges" => [],
          "class" => "Organization",
          "id" => "61127ddee9f485e2009dbf22",
          "logo" => "https://demo-static.data.gouv.fr/avatars/2f/6d1820648b49f69bba027206a882c8-original.jpg",
          "logo_thumbnail" => "https://demo-static.data.gouv.fr/avatars/2f/6d1820648b49f69bba027206a882c8-100.jpg",
          "name" => "Citadine-Electrique.com",
          "page" => "https://demo.data.gouv.fr/fr/organizations/citadine-electrique-com/",
          "slug" => "citadine-electrique-com",
          "uri" => "https://demo.data.gouv.fr/api/1/organizations/citadine-electrique-com/"
        },
        "owner" => %{"name" => "Citadine-Electrique.com"},
        "page" => "https://demo.data.gouv.fr/fr/reuses/https-citadine-electrique-com/",
        "private" => false,
        "slug" => "https-citadine-electrique-com",
        "tags" => ["borne-de-recharge-electrique", "voiture-electrique"],
        "title" => "https://citadine-electrique.com/",
        "topic" => "transport_and_mobility",
        "type" => "application",
        "uri" => "https://demo.data.gouv.fr/api/1/reuses/https-citadine-electrique-com/",
        "url" => "https://citadine-electrique.com/"
      }
    ]
  end
end
