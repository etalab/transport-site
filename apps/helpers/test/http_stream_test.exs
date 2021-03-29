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
    [content] = HTTPStream.get(url) |> Stream.into([]) |> Enum.to_list()
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
    data = HTTPStream.get(url) |> Stream.into([]) |> Enum.to_list()
    # We should have multiple chunks (different ones) on the receiving end
    # due to how the client app buffering works
    assert data |> Enum.count() >= 5
    # once re-joined, the server output should equal what we receive
    assert data |> Enum.join() == large_content_in_n_chunks |> Enum.join()
  end
end
