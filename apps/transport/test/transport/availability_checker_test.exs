defmodule Transport.AvailabilityCheckerTest do
  use ExUnit.Case, async: false
  import Mock
  import Mox
  alias Transport.AvailabilityChecker

  setup :verify_on_exit!

  test "HEAD supported, 200" do
    mock_head_with_status(200)
    assert AvailabilityChecker.available?("GTFS", "url200")
  end

  test "HEAD supported, 400" do
    mock_head_with_status(400)
    refute AvailabilityChecker.available?("GTFS", "url400")
  end

  test "HEAD supported, 500" do
    mock_head_with_status(500)
    refute AvailabilityChecker.available?("GTFS", "url500")
  end

  test "HEAD supported, 204" do
    mock_head_with_status(204)
    refute AvailabilityChecker.available?("GTFS", "url204")
  end

  describe "SIRI or SIRI Lite resource" do
    test "401" do
      Transport.HTTPoison.Mock
      |> expect(:get, 2, fn _url, [], [follow_redirect: true] ->
        {:ok, %HTTPoison.Response{status_code: 401}}
      end)

      assert AvailabilityChecker.available?("SIRI", "url401")
      assert AvailabilityChecker.available?("SIRI Lite", "url401")
    end

    test "405" do
      Transport.HTTPoison.Mock
      |> expect(:get, 2, fn _url, [], [follow_redirect: true] ->
        {:ok, %HTTPoison.Response{status_code: 405}}
      end)

      assert AvailabilityChecker.available?("SIRI", "url405")
      assert AvailabilityChecker.available?("SIRI Lite", "url405")
    end

    test "303 response" do
      # See https://github.com/edgurgel/httpoison/issues/171#issuecomment-244029927
      Transport.HTTPoison.Mock
      |> expect(:get, fn _url, [], [follow_redirect: true] ->
        {:error, %HTTPoison.Error{reason: {:invalid_redirection, nil}}}
      end)

      assert AvailabilityChecker.available?("SIRI", "url303")
    end
  end

  test "HEAD NOT supported, fallback on stream method" do
    test_fallback_to_stream(405)
  end

  test "HEAD requires auth, fallback on stream method" do
    test_fallback_to_stream(401)
    test_fallback_to_stream(403)
  end

  test "redirection for Google Drive" do
    expect(Transport.HTTPoison.Mock, :head, fn _url, [], [follow_redirect: true, hackney: [force_redirect: true]] ->
      {:ok, %HTTPoison.Response{status_code: 200}}
    end)

    assert AvailabilityChecker.available?("GTFS", "https://drive.google.com/test_url")
  end

  defp mock_head_with_status(status_code) do
    expect(Transport.HTTPoison.Mock, :head, fn _url, [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: status_code}}
    end)
  end

  defp test_fallback_to_stream(status_code) do
    mock_head_with_status(status_code)

    streamer_mock = fn _url -> {:ok, 200} end

    with_mock HTTPStreamV2, fetch_status_follow_redirect: streamer_mock do
      assert AvailabilityChecker.available?("GTFS", "url")
      assert_called_exactly(HTTPStreamV2.fetch_status_follow_redirect(:_), 1)
    end
  end
end
