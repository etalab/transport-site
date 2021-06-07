defmodule Transport.AvailabilityCheckerTest do
  use ExUnit.Case
  import Mock
  alias Transport.AvailabilityChecker

  test "head supported, 200", _ do
    mock = fn _url, [], _options ->
      {:ok, %HTTPoison.Response{body: "{}", status_code: 200}}
    end

    with_mock HTTPoison, head: mock do
      assert AvailabilityChecker.available?(%{"url" => "url200"})
      assert_called_exactly(HTTPoison.head(:_, :_, :_), 1)
    end
  end

  test "head supported, 400", _ do
    mock = fn _url, [], _options ->
      {:ok, %HTTPoison.Response{body: "{}", status_code: 400}}
    end

    with_mock HTTPoison, head: mock do
      refute AvailabilityChecker.available?(%{"url" => "url400"})
      assert_called_exactly(HTTPoison.head(:_, :_, :_), 1)
    end
  end

  test "head supported, 500", _ do
    mock = fn _url, [], _options ->
      {:ok, %HTTPoison.Response{body: "{}", status_code: 500}}
    end

    with_mock HTTPoison, head: mock do
      refute AvailabilityChecker.available?(%{"url" => "url500"})
      assert_called_exactly(HTTPoison.head(:_, :_, :_), 1)
    end
  end

  test "head NOT supported, fallback on stream method", _ do
    httpoison_mock = fn _url, [], _options ->
      {:ok, %HTTPoison.Response{body: "{}", status_code: 405}}
    end

    streamer_mock = fn _url ->
      {:ok, 200}
    end

    with_mock HTTPoison, head: httpoison_mock do
      with_mock HTTPStreamV2, fetch_status_follow_redirect: streamer_mock do
        assert AvailabilityChecker.available?(%{"url" => "url405"})
        assert_called_exactly(HTTPoison.head(:_, :_, :_), 1)
        assert_called_exactly(HTTPStreamV2.fetch_status_follow_redirect(:_), 1)
      end
    end
  end
end
