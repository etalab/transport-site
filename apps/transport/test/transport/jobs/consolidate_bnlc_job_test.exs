defmodule Transport.Test.Transport.Jobs.ConsolidateBNLCJobTest do
  use ExUnit.Case, async: true
  import Mox
  alias Transport.Jobs.ConsolidateBNLCJob

  doctest ConsolidateBNLCJob, import: true
  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "dataset_slugs" do
    Transport.HTTPoison.Mock
    |> expect(
      :get!,
      fn "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/main/datasets.csv" ->
        body = """
        dataset_url
        https://www.data.gouv.fr/fr/datasets/foo/
        https://www.data.gouv.fr/fr/datasets/bar
        https://www.data.gouv.fr/fr/datasets/bar/
        """

        %HTTPoison.Response{status_code: 200, body: body}
      end
    )

    assert ["foo", "bar"] == ConsolidateBNLCJob.dataset_slugs()
  end

  test "dataset_details" do
    # foo is a 200 response including a resource with an appropriate schema
    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, "https://demo.data.gouv.fr/api/1/datasets/foo/", "", [], [follow_redirect: true] ->
      body = %{"slug" => "foo", "resources" => [%{"schema" => %{"name" => "etalab/schema-lieux-covoiturage"}}]}
      {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(body)}}
    end)

    # bar is a 200-response with a resource without a schema
    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, "https://demo.data.gouv.fr/api/1/datasets/bar/", "", [], [follow_redirect: true] ->
      body = %{"slug" => "bar", "resources" => [%{"format" => "csv"}]}
      {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(body)}}
    end)

    # baz returns an error
    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, "https://demo.data.gouv.fr/api/1/datasets/baz/", "", [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: 404, body: ""}}
    end)

    assert %{
             errors: [
               "https://www.data.gouv.fr/fr/datasets/baz/",
               %{"resources" => [%{"format" => "csv"}], "slug" => "bar"}
             ],
             ok: [%{"resources" => [%{"schema" => %{"name" => "etalab/schema-lieux-covoiturage"}}], "slug" => "foo"}]
           } == ConsolidateBNLCJob.dataset_details(["foo", "bar", "baz"])
  end

  test "valid_datagouv_resources" do
    datasets_details = [
      dataset_details = %{
        "resources" => [
          resource = %{
            "schema" => %{"name" => "etalab/schema-lieux-covoiturage"},
            "url" => url = "https://example.com/file.csv"
          },
          # Ignored, not the expected schema
          %{"format" => "GTFS"},
          other_resource = %{
            "schema" => %{"name" => "etalab/schema-lieux-covoiturage"},
            "url" => other_url = "https://example.com/other_file.csv"
          }
        ],
        "slug" => "foo"
      },
      # Another dataset where we will simulate a validation error (validator's fault)
      other_dataset_details = %{
        "resources" => [
          validation_error_resource = %{
            "schema" => %{"name" => "etalab/schema-lieux-covoiturage"},
            "url" => file_error_url = "https://example.com/file_error.csv"
          }
        ],
        "slug" => "bar"
      }
    ]

    Shared.Validation.TableSchemaValidator.Mock
    |> expect(:validate, fn "etalab/schema-lieux-covoiturage", ^url ->
      %{"has_errors" => false}
    end)

    Shared.Validation.TableSchemaValidator.Mock
    |> expect(:validate, fn "etalab/schema-lieux-covoiturage", ^other_url ->
      %{"has_errors" => true}
    end)

    Shared.Validation.TableSchemaValidator.Mock
    |> expect(:validate, fn "etalab/schema-lieux-covoiturage", ^file_error_url ->
      nil
    end)

    assert %{
             errors: [
               {:validation_error, other_dataset_details, validation_error_resource},
               {:error, dataset_details, other_resource}
             ],
             ok: [{dataset_details, resource}]
           } == ConsolidateBNLCJob.valid_datagouv_resources(datasets_details)
  end

  test "download_resources" do
    dataset_detail = %{
      "resources" => [
        resource = %{
          "id" => resource_id = Ecto.UUID.generate(),
          "schema" => %{"name" => "etalab/schema-lieux-covoiturage"},
          "url" => url = "https://example.com/file.csv"
        }
      ],
      "slug" => "foo"
    }

    Transport.HTTPoison.Mock
    |> expect(:get, fn ^url, [], [follow_redirect: true] ->
      body = """
      foo,bar
      1,2
      """

      {:ok, %HTTPoison.Response{status_code: 200, body: body}}
    end)

    resources_details = [{dataset_detail, resource}]

    assert %{
             errors: [],
             ok: [
               {^dataset_detail,
                %{"id" => ^resource_id, "url" => ^url, "csv_separator" => ?,, "tmp_download_path" => tmp_download_path}}
             ]
           } = ConsolidateBNLCJob.download_resources(resources_details)

    assert String.ends_with?(tmp_download_path, "consolidate_bnlc_#{resource_id}")
    assert File.exists?(tmp_download_path)
  end

  test "guess_csv_separator" do
    assert ?, ==
             ConsolidateBNLCJob.guess_csv_separator("""
             foo,bar
             1,2
             """)

    assert ?; ==
             ConsolidateBNLCJob.guess_csv_separator("""
             foo;bar
             1;2
             """)

    assert ?; ==
             ConsolidateBNLCJob.guess_csv_separator("""
             "foo";"bar"
             1;2
             """)
  end
end
