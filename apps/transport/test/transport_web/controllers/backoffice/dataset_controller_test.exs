defmodule TransportWeb.Backoffice.DatasetControllerTest do
  use TransportWeb.ConnCase, async: true
  alias TransportWeb.Router.Helpers, as: Routes
  import DB.Factory
  import Mox
  import Ecto.Query

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    # Using the real implementation for the moment, and then it fallsback on HTTPoison.Mock
    Mox.stub_with(Datagouvfr.Client.Datasets.Mock, Datagouvfr.Client.Datasets.External)
    :ok
  end

  test "update a dataset custom title", %{conn: conn} do
    dataset = insert(:dataset, custom_title: "title 1", slug: slug = "https://example.com/slug")

    set_expectations()

    conn
    |> setup_admin_in_session()
    |> post(Routes.backoffice_dataset_path(conn, :post, dataset.id), %{
      "form" => %{
        "custom_title" => "new title",
        "url" => slug,
        "type" => "public-transit"
      }
    })

    # the title has been updated, the dataset_id has not changed
    assert %DB.Dataset{custom_title: "new title"} = DB.Repo.reload!(dataset)
  end

  test "update a dataset slug", %{conn: conn} do
    dataset =
      %{id: dataset_id} =
      insert(:dataset,
        is_active: false,
        datagouv_id: Ecto.UUID.generate(),
        custom_title: "title",
        slug: "https://example.com/slug"
      )

    datagouv_id_2 = "datagouv_id_2_" <> Ecto.UUID.generate()
    slug_2 = "slug_2_" <> Ecto.UUID.generate()

    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, url, _, _, _ ->
      assert url == "https://demo.data.gouv.fr/api/1/datasets/#{slug_2}/"
      # the slug changes, the datagouv_id too
      {:ok, %HTTPoison.Response{body: ~s({"id": "#{datagouv_id_2}"}), status_code: 200}}
    end)

    Transport.HTTPoison.Mock
    |> expect(:get!, fn url, _, _ ->
      assert "https://demo.data.gouv.fr/api/1/datasets/#{datagouv_id_2}/" == url

      %HTTPoison.Response{
        body: Jason.encode!(datagouv_dataset_response(%{"id" => datagouv_id_2, "slug" => slug_2, "resources" => []})),
        status_code: 200
      }
    end)

    Datagouvfr.Client.CommunityResources.Mock
    |> expect(:get, fn _ -> {:ok, []} end)

    conn
    |> setup_admin_in_session()
    |> post(Routes.backoffice_dataset_path(conn, :post, dataset.id), %{
      "form" => %{
        "custom_title" => "title",
        "url" => "https://example.com/#{slug_2}",
        "type" => "public-transit"
      }
    })

    # the slug and datagouv_id have been updated, but the dataset_id has not changed
    # `is_active` has been changed to `true`
    assert %DB.Dataset{
             id: ^dataset_id,
             datagouv_id: ^datagouv_id_2,
             custom_title: "title",
             slug: ^slug_2,
             is_active: true
           } = DB.Repo.reload!(dataset)
  end

  test "update a dataset custom tags, organization type", %{conn: conn} do
    dataset = insert(:dataset, slug: slug = "slug")

    set_expectations()

    conn
    |> setup_admin_in_session()
    |> post(Routes.backoffice_dataset_path(conn, :post, dataset.id), %{
      "form" => %{
        "custom_title" => "title",
        "url" => slug,
        "type" => "public-transit",
        "custom_tags[0]" => tag1 = "top",
        "custom_tags[1]" => tag2 = "super",
        "organization_type" => organization_type = "AOM"
      }
    })

    # the custom tags have been saved
    assert %DB.Dataset{custom_tags: [^tag1, ^tag2], organization_type: ^organization_type} = DB.Repo.reload!(dataset)
  end

  test "update a dataset siren and legal owners", %{conn: conn} do
    dataset = insert(:dataset, slug: slug = "slug")

    aom_0 = insert(:aom)
    aom_1 = insert(:aom)
    region_0 = insert(:region)
    region_1 = insert(:region)

    set_expectations()

    siren = "552049447"

    conn
    |> setup_admin_in_session()
    |> post(Routes.backoffice_dataset_path(conn, :post, dataset.id), %{
      "form" => %{
        "custom_title" => "title",
        "url" => slug,
        "type" => "public-transit",
        "legal_owner_company_siren" => siren,
        "legal_owners_aom[0]" => aom_0.id |> Integer.to_string(),
        "legal_owners_aom[1]" => aom_1.id |> Integer.to_string(),
        "legal_owners_region[0]" => region_0.id |> Integer.to_string(),
        "legal_owners_region[1]" => region_1.id |> Integer.to_string()
      }
    })

    # the legal owners have been saved
    assert %DB.Dataset{legal_owner_company_siren: ^siren, legal_owners_aom: aoms, legal_owners_region: regions} =
             DB.Dataset |> preload([:legal_owners_aom, :legal_owners_region]) |> DB.Repo.get!(dataset.id)

    assert aoms |> Enum.map(& &1.id) |> Enum.sort() == [aom_0.id, aom_1.id]
    assert regions |> Enum.map(& &1.id) |> Enum.sort() == [region_0.id, region_1.id]
  end

  defp set_expectations do
    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, "https://demo.data.gouv.fr/api/1/datasets/slug/", _, _, _ ->
      {:ok, %HTTPoison.Response{body: ~s({"id": "datagouv_id"}), status_code: 200}}
    end)

    Transport.HTTPoison.Mock
    |> expect(:get!, fn "https://demo.data.gouv.fr/api/1/datasets/datagouv_id/", _, _ ->
      %HTTPoison.Response{
        body: Jason.encode!(datagouv_dataset_response(%{"resources" => []})),
        status_code: 200
      }
    end)

    Datagouvfr.Client.CommunityResources.Mock
    |> expect(:get, fn _ -> {:ok, []} end)
  end
end
