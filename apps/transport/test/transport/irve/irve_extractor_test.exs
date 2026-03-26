defmodule Transport.IRVE.ExtractorTest do
  use ExUnit.Case, async: true
  import Mox
  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "paginates data gouv to retrieve all relevant resources metadata via #resources call" do
    # NOTE: pagination is not really tested at the moment, but that's good enough for the current scope of use

    # initial request helps computing the number of pages & generating urls
    Transport.Req.Mock
    |> expect(:get!, fn _request, options ->
      assert options[:url] == "https://www.data.gouv.fr/api/1/datasets/?schema=etalab/schema-irve-statique&page_size=3"
      %Req.Response{status: 200, body: DB.Factory.IRVE.build_datagouv_initial_pagination_payload(page_size: 3)}
    end)

    # next requests are same queries but paginated and helping
    Transport.Req.Mock
    |> expect(:get!, fn _request, options ->
      assert options[:url] ==
               "https://www.data.gouv.fr/api/1/datasets/?schema=etalab/schema-irve-statique&page=1&page_size=3"

      %Req.Response{
        status: 200,
        body: DB.Factory.IRVE.build_datagouv_page_payload()
      }
    end)

    assert Transport.IRVE.Extractor.datagouv_resources(page_size: 3) == [
             %{
               dataset_id: "the-dataset-id",
               dataset_title: "the-dataset-title",
               dataset_organisation_id: "the-org-id",
               dataset_organisation_name: "the-org",
               dataset_organisation_url: "http://the-org",
               datagouv_organization_or_owner: "the-org",
               datagouv_last_modified: "2024-02-29T07:43:59.660000+00:00",
               resource_id: "the-resource-id",
               resource_title: "the-resource-title",
               schema_name: "etalab/schema-irve-statique",
               schema_version: "2.3.0",
               filetype: "file",
               url: "https://static.data.gouv.fr/resources/some-irve-url-2024/data.csv",
               valid: true,
               validation_date: "2024-02-24",
               last_modified: "2024-02-29T07:43:59.660000+00:00"
             },
             %{
               valid: true,
               last_modified: "2024-02-29T07:43:59.660000+00:00",
               url: "https://static.data.gouv.fr/resources/another-irve-url-2024/data.csv",
               dataset_id: "another-dataset-id",
               dataset_organisation_id: "another-org-id",
               dataset_organisation_name: "another-org",
               dataset_organisation_url: "http://another-org",
               datagouv_organization_or_owner: "another-org",
               datagouv_last_modified: "2024-02-29T07:43:59.660000+00:00",
               resource_id: "another-resource-id",
               dataset_title: "another-dataset-title",
               schema_version: "2.3.0",
               schema_name: "etalab/schema-irve-statique",
               resource_title: "another-resource-title",
               filetype: "file",
               validation_date: "2024-02-24"
             },
             %{
               dataset_id: "individual-published-dataset-id",
               dataset_organisation_id: "???",
               dataset_organisation_name: "???",
               dataset_organisation_url: "???",
               datagouv_organization_or_owner: "Guy Who loves IRVE",
               datagouv_last_modified: "2024-02-29T07:43:59.660000+00:00",
               dataset_title: "individual-published-dataset-title",
               filetype: "file",
               last_modified: "2024-02-29T07:43:59.660000+00:00",
               resource_id: "individual-published-resource-id",
               resource_title: "individual-published-resource-title",
               schema_name: "etalab/schema-irve-statique",
               schema_version: "2.3.0",
               url: "https://static.data.gouv.fr/resources/individual-published-irve-url-2024/data.csv",
               valid: true,
               validation_date: "2024-02-24"
             }
           ]
  end

  test "given a list of resources, download & analyze them via #download_and_parse_all" do
    resources = [
      orig_resource = %{
        url: expected_url = "https://static.data.gouv.fr/resources/something/something.csv",
        dataset_id: "the-dataset-id",
        dataset_title: "the-dataset-title",
        resource_id: "the-resource-id",
        resource_title: "the-resource-title",
        valid: true
      }
    ]

    Transport.Req.Mock
    |> expect(:get!, fn _request, options ->
      assert options[:url] == expected_url

      %Req.Response{
        status: 200,
        body: "id_pdc_itinerance\nFR123\nFR456\nFR789"
      }
    end)

    # parsed resources must be enriched with line count & index, and url removed
    assert Transport.IRVE.Extractor.download_and_parse_all(resources) == [
             orig_resource
             |> Map.put(:index, 0)
             |> Map.put(:line_count, 3)
             |> Map.put(:http_status, 200)
             |> Map.delete(:url)
           ]
  end

  test "handles non-200 response" do
    resources = [
      orig_resource = %{
        url: expected_url = "https://static.data.gouv.fr/resources/something/something.csv",
        dataset_id: "the-dataset-id",
        dataset_title: "the-dataset-title",
        resource_id: "the-resource-id",
        resource_title: "the-resource-title",
        valid: true
      }
    ]

    Transport.Req.Mock
    |> expect(:get!, fn _request, options ->
      assert options[:url] == expected_url

      %Req.Response{
        status: 404,
        body: "there is nothing here"
      }
    end)

    # parsed resources must be enriched with line count & index, and url removed
    assert Transport.IRVE.Extractor.download_and_parse_all(resources) == [
             orig_resource
             |> Map.put(:index, 0)
             |> Map.put(:http_status, 404)
             |> Map.delete(:url)
           ]
  end
end
