defmodule Transport.ImportDataTest do
  use ExUnit.Case, async: true
  alias Transport.ImportData
  import Mock
  import TransportWeb.Factory
  doctest ImportData

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
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
