defmodule TransportWeb.API.FeaturesControllerTest do
  use TransportWeb.ConnCase, async: true
  alias TransportWeb.API.Router.Helpers

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "autocomplete", %{conn: conn} do
    assert [] == DB.Repo.all(DB.FeatureUsage)

    assert conn
           |> post(Helpers.features_path(conn, :autocomplete, %{name: "Foo", type: "commune", contact_id: nil}))
           |> json_response(200) == %{"status" => "ok"}

    assert [
             %DB.FeatureUsage{
               feature: :autocomplete,
               metadata: %{"name" => "Foo", "type" => "commune"},
               contact_id: nil
             }
           ] = DB.Repo.all(DB.FeatureUsage)
  end
end
