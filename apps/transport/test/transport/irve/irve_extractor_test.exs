defmodule Transport.IRVE.ExtractorTest do
  use ExUnit.Case, async: true
  import Mox
  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  def build_initial_pagination_payload(page_size: page_size) do
    %{
      "data" => [],
      "next_page" => nil,
      "page" => 1,
      "total" => 1,
      "page_size" => page_size
    }
  end

  def build_page_payload do
    %{
      "data" => [
        %{
          "id" => "the-dataset-id",
          "title" => "the-dataset-title",
          "organization" => %{
            "name" => "the-org",
            "page" => "http://the-org"
          },
          "resources" => [
            %{
              "schema" => %{
                "name" => "etalab/schema-irve-statique",
                "version" => "2.3.0"
              },
              "id" => "the-resource-id",
              "title" => "the-resource-title",
              "extras" => %{
                "validation-report:valid_resource" => true,
                "validation-report:validation_date" => "2024-02-24"
              },
              "filetype" => "file",
              "last_modified" => "2024-02-29T07:43:59.660000+00:00",
              "url" => "https://static.data.gouv.fr/resources/some-irve-url-2024/data.csv"
            }
          ]
        }
      ]
    }
  end

  test "paginates data gouv to retrieve all relevant resources metadata via #resources call" do
    # NOTE: pagination is not really tested at the moment, but that's good enough for the current scope of use

    # initial request helps computing the number of pages & generating urls
    Transport.Req.Mock
    |> expect(:get!, fn _request, options ->
      assert options[:url] == "https://www.data.gouv.fr/api/1/datasets/?schema=etalab/schema-irve-statique&page_size=2"
      %Req.Response{status: 200, body: build_initial_pagination_payload(page_size: 2)}
    end)

    # next requests are same queries but paginated and helping
    Transport.Req.Mock
    |> expect(:get!, fn _request, options ->
      assert options[:url] ==
               "https://www.data.gouv.fr/api/1/datasets/?schema=etalab/schema-irve-statique&page=1&page_size=2"

      %Req.Response{
        status: 200,
        body: build_page_payload()
      }
    end)

    assert Transport.IRVE.Extractor.resources(page_size: 2) == [
             %{
               dataset_id: "the-dataset-id",
               dataset_title: "the-dataset-title",
               dataset_organisation_name: "the-org",
               dataset_organisation_url: "http://the-org",
               resource_id: "the-resource-id",
               resource_title: "the-resource-title",
               schema_name: "etalab/schema-irve-statique",
               schema_version: "2.3.0",
               filetype: "file",
               url: "https://static.data.gouv.fr/resources/some-irve-url-2024/data.csv",
               valid: true,
               validation_date: "2024-02-24",
               last_modified: "2024-02-29T07:43:59.660000+00:00"
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
