defmodule Transport.ImportDataTest do
  use ExUnit.Case, async: true
  alias Transport.ImportData
  import Mock
  import TransportWeb.Factory
  doctest ImportData

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "end-to-end test" do
    # NOTE: we should ultimately use "valid" datasets (which went through the changesets),
    # because currently this is not the case
    dataset = insert(:dataset, datagouv_id: "some-id")
    dataset = insert(:dataset, datagouv_id: "some-other-id")
    assert DB.Repo.aggregate(DB.Dataset, :count, :id) == 2

    # For now, using mocking as an intermediate step to using a real separate mock udata implementation
    # (but there's too much to refactor for now).
    payload = build(:datagouv_api_get)

    mock = fn _, _, _ ->
      {:ok, %HTTPoison.Response{body: payload, status_code: 200}}
    end

    # first call must result in call to third party
    with_mock HTTPoison, get: mock do
      ImportData.import_all_datasets()
    end
  end

  test "the available? function with HTTP request", _ do
    mock = fn url ->
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
      assert_called_exactly(HTTPoison.head(:_), 3)
    end
  end
end
