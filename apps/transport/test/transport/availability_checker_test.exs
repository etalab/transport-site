defmodule Transport.AvailabilityCheckerTest do
  use ExUnit.Case, async: false
  import Mock
  alias Transport.AvailabilityChecker

  test "head supported, 200", _ do
    mock = fn _url, [], _options ->
      {:ok, %HTTPoison.Response{body: "{}", status_code: 200}}
    end

    with_mock HTTPoison, head: mock do
      assert AvailabilityChecker.available?("url200")
      assert_called_exactly(HTTPoison.head(:_, :_, :_), 1)
    end
  end

  test "head supported, 400", _ do
    mock = fn _url, [], _options ->
      {:ok, %HTTPoison.Response{body: "{}", status_code: 400}}
    end

    with_mock HTTPoison, head: mock do
      refute AvailabilityChecker.available?("url400")
      assert_called_exactly(HTTPoison.head(:_, :_, :_), 1)
    end
  end

  test "head supported, 500", _ do
    mock = fn _url, [], _options ->
      {:ok, %HTTPoison.Response{body: "{}", status_code: 500}}
    end

    with_mock HTTPoison, head: mock do
      refute AvailabilityChecker.available?("url500")
      assert_called_exactly(HTTPoison.head(:_, :_, :_), 1)
    end
  end

  test "head NOT supported, fallback on stream method", _ do
    test_fallback_to_stream(405)
  end

  test "head requires auth, fallback on stream method", _ do
    test_fallback_to_stream(401)
    test_fallback_to_stream(403)
  end

  defp test_fallback_to_stream(status_code) do
    httpoison_mock = fn _url, [], _options ->
      {:ok, %HTTPoison.Response{body: "{}", status_code: status_code}}
    end

    streamer_mock = fn _url ->
      {:ok, 200}
    end

    with_mock HTTPoison, head: httpoison_mock do
      with_mock HTTPStreamV2, fetch_status_follow_redirect: streamer_mock do
        assert AvailabilityChecker.available?("url")
        assert_called_exactly(HTTPoison.head(:_, :_, :_), 1)
        assert_called_exactly(HTTPStreamV2.fetch_status_follow_redirect(:_), 1)
      end
    end
  end
end
