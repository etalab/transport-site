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
      %{
        "resources" => [
          %{"schema" => %{"name" => "etalab/schema-lieux-covoiturage"}, "url" => url = "https://example.com/file.csv"}
        ],
        "slug" => "foo"
      }
    ]

    Shared.Validation.TableSchemaValidator.Mock
    |> expect(:validate, fn "etalab/schema-lieux-covoiturage", ^url ->
      %{"has_errors" => false}
    end)

    assert [] == ConsolidateBNLCJob.valid_datagouv_resources(datasets_details)
  end
end
