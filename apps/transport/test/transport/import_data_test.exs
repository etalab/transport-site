defmodule Transport.ImportDataTest do
  use ExUnit.Case, async: true
  alias Transport.ImportData
  import Mock
  import TransportWeb.Factory
  import ExUnit.CaptureLog
  doctest ImportData

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  def generate_payload() do
    %{
      "title" => "dataset1",
      "id" => "dataset1_id",
      "slug" => "dataset-slug",
      "resources" => [
        %{
          "title" => "resource1",
          "url" => "http://localhost:4321/resource1",
          "id" => "resource1_id"
        }
      ]
    }
  end

  @tag :focus
  test "hello world des imports" do
    # _dataset =
    #   insert(
    #     # hello
    #     :dataset,
    #     datagouv_id: datagouv_id = "some-id",
    #     national_dataset: "true"
    #   )

    insert(:region, nom: "National")

    Transport.Inspect.pretty_inspect(DB.Repo.all(DB.Region))

    {:ok, changes} =
      DB.Dataset.changeset(%{
        "datagouv_id" => datagouv_id = "some-id",
        "slug" => "ma_limace",
        "national_dataset" => "true"
        # "insee" => "38185"
      })

    DB.Repo.insert!(changes)

    assert DB.Repo.aggregate(DB.Dataset, :count, :id) == 1
    assert DB.Repo.aggregate(DB.Resource, :count, :id) == 0

    http_mock = fn url, [], hackney: [follow_redirect: true] ->
      base_url = Application.get_env(:transport, :datagouvfr_site)
      expected_url = "#{base_url}/api/1/datasets/#{datagouv_id}/"
      assert url == expected_url

      {:ok, %HTTPoison.Response{body: Jason.encode!(generate_payload())}}
    end

    http_head_mock = fn url, _, _ ->
      assert url == "http://localhost:4321/resource1"
      {:ok, %HTTPoison.Response{status_code: 200}}
    end

    http_stream_mock = fn url ->
      assert url == "http://localhost:4321/resource1"

      %{
        status: 200,
        hash: "resource1_hash"
      }
    end

    with_mock HTTPoison, get: http_mock, head: http_head_mock do
      with_mock Datagouvfr.Client.CommunityResources, get: fn _ -> {:ok, []} end do
        with_mock HTTPStreamV2, fetch_status_and_hash: http_stream_mock do
          # TODO check mocks are called once
          Transport.Inspect.pretty_inspect(ImportData.import_all_datasets())
        end
      end
    end
  end

  test "error while connecting to datagouv server"

  test "with community resources"

  describe "import_all_test" do
    test "logs unmanaged exceptions" do
      # NOTE: we should ultimately use "valid" datasets (which went through the changesets),
      # because currently this is not the case
      insert(:dataset, datagouv_id: "some-id")
      assert DB.Repo.aggregate(DB.Dataset, :count, :id) == 1

      # For now, using mocking as an intermediate step to using a real separate mock udata implementation
      # (but there's too much to refactor for now).
      payload = :datagouv_api_get |> build() |> Jason.encode!()

      mock = fn _, _, _ ->
        {:ok, %HTTPoison.Response{body: payload, status_code: 200}}
      end

      with_mock Sentry, capture_message: fn _, _ -> nil end do
        with_mock HTTPoison, get: mock do
          logs =
            capture_log(fn ->
              ImportData.import_all_datasets()
            end)

          logs = logs |> String.split("\n")
          assert logs |> Enum.at(0) =~ "Unmanaged exception during import"
          # NOTE: for now, relying on a specific error that we're triggering due to missing key, but it's
          # far from ideal and it would be better to have something more explicit
          assert logs |> Enum.at(1) =~ "no function clause matching in Transport.ImportData.get_valid_resources/2"
        end

        assert_called_exactly(Sentry.capture_message(:_, :_), 1)
      end
    end
  end

  test "the available? function with HTTP request", _ do
    mock = fn url, [], options ->
      # temporary fix for https://github.com/etalab/transport-site/issues/1564
      assert options == [ssl: [versions: [:"tlsv1.2"]]]

      case url do
        'url200' -> {:ok, %HTTPoison.Response{body: "{}", status_code: 200}}
        'url300' -> {:ok, %HTTPoison.Response{body: "{}", status_code: 300}}
        'url400' -> {:ok, %HTTPoison.Response{body: "{}", status_code: 400}}
      end
    end

    with_mock HTTPoison, head: mock do
      assert ImportData.available?(%{"url" => 'url200'})
      assert ImportData.available?(%{"url" => 'url300'})
      refute ImportData.available?(%{"url" => 'url400'})
      assert_called_exactly(HTTPoison.head(:_, :_, :_), 3)
    end
  end
end
