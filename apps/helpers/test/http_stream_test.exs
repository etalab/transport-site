defmodule HTTPStream.Test do
  use ExUnit.Case, async: true

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  # Bare minimum test to lock down the behaviour before upgrading Mint
  test "fetch content", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/", fn conn ->
      Plug.Conn.resp(conn, 200, "Some content")
    end)

    url = "http://localhost:#{bypass.port}/"
    [content] = url |> HTTPStream.get() |> Stream.into([]) |> Enum.to_list()
    assert content == "Some content"
  end

  # this is a different code path in current HTTPStream code
  test "fetch content with url query", %{bypass: bypass} do
    url = "/hello"
    query = "var=value"

    Bypass.expect_once(bypass, "GET", url, fn conn ->
      assert conn.query_string == query
      Plug.Conn.resp(conn, 200, "Some content")
    end)

    url = "http://localhost:#{bypass.port}#{url}?#{query}"
    [content] = url |> HTTPStream.get() |> Stream.into([]) |> Enum.to_list()
    assert content == "Some content"
  end

  test "fetch content using chunked encoding for streaming", %{bypass: bypass} do
    # a large payload that the server sends back into 2 large chunks
    large_content_in_n_chunks = [
      String.duplicate("a", 1024 * 1024 + 1),
      String.duplicate("a", 1024 * 1024 + 1)
    ]

    # See https://en.wikipedia.org/wiki/Chunked_transfer_encoding
    #
    # "Chunked encoding has the benefit that it is not necessary to generate
    #  the full content before writing the header, as it allows streaming of
    #  content as chunks and explicitly signaling the end of the content"
    #
    Bypass.expect_once(bypass, "GET", "/", fn conn ->
      # see https://hexdocs.pm/plug/Plug.Conn.html#send_chunked/2
      conn = Plug.Conn.send_chunked(conn, 200)

      # see https://hexdocs.pm/plug/Plug.Conn.html#chunk/2
      Enum.reduce_while(large_content_in_n_chunks, conn, fn chunk, conn ->
        case Plug.Conn.chunk(conn, chunk) do
          {:ok, conn} ->
            {:cont, conn}

          {:error, :closed} ->
            {:halt, conn}
        end
      end)
    end)

    url = "http://localhost:#{bypass.port}/"
    data = url |> HTTPStream.get() |> Stream.into([]) |> Enum.to_list()
    # We should have multiple chunks (different ones) on the receiving end
    # due to how the client app buffering works
    assert data |> Enum.count() >= 5
    # once re-joined, the server output should equal what we receive
    assert data |> Enum.join() == large_content_in_n_chunks |> Enum.join()
  end

  test "error case returns nil (BOGUS ???)" do
    # ⚠️ adding this test but I think the behaviour of the tested code is not what we need:
    # the computed checksum is likely incorrect (to be investigated).
    buggy_url = "http://localhost:aaaa"

    data = buggy_url |> HTTPStream.get() |> Stream.into([]) |> Enum.to_list()
    assert data == []
  end

  test "status 404 (BOGUS ???)", %{bypass: bypass} do
    # ⚠️ apparently 404 just returns the data, but there is no trace
    # that the 404 occurred. I am not sure what the implications are, since
    # the target resource computed checksum will actually be the one of the 404 result

    Bypass.expect_once(bypass, "GET", "/", fn conn ->
      Plug.Conn.resp(conn, 404, "NOT FOUND")
    end)

    url = "http://localhost:#{bypass.port}/"
    [content] = url |> HTTPStream.get() |> Stream.into([]) |> Enum.to_list()
    assert content == "NOT FOUND"
  end
end
