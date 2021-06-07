defmodule HTTPStreamV2.Test do
  use ExUnit.Case, async: true

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  test "streams the content and compute expected information", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("hello", "header")
      |> Plug.Conn.resp(302, "Contenu éphémère")
    end)

    url = "http://localhost:#{bypass.port}/"
    result = HTTPStreamV2.fetch_status_and_hash(url)

    assert result.status == 302
    assert result.hash == :sha256 |> :crypto.hash("Contenu éphémère") |> Base.encode16 |> String.downcase
    assert result.body_byte_size == ("Contenu éphémère" |> byte_size())
    headers = result.headers
    |> Enum.filter(fn({key, _val}) -> key == "hello" end)

    assert headers == [{"hello", "header"}]
  end

  describe "get a request status by streaming it" do
    test "simple 200 response", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("hello", "header")
        |> Plug.Conn.resp(200, "Contenu de la réponse")
      end)

      url = "http://localhost:#{bypass.port}/"

      result = HTTPStreamV2.fetch_status(url)
      assert result == {:ok, %{status: 200}}

      result_follow_redirect = HTTPStreamV2.fetch_status_follow_redirect(url)
      assert result_follow_redirect == {:ok, 200}
    end

    test "redirect response", %{bypass: bypass} do
      url = "http://localhost:#{bypass.port}/"

      Bypass.expect(bypass, "GET", "/", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("Location", "#{url}here")
        |> Plug.Conn.resp(301, "va voir ailleurs si j'y suis")
      end)

      Bypass.expect_once(bypass, "GET", "/here", fn conn ->
        conn
        |> Plug.Conn.resp(200, "gagné")
      end)

      result = HTTPStreamV2.fetch_status(url)
      assert result == {:ok, %{status: 301, location: "#{url}here"}}

      # get the status following redirection
      result_follow_redirect = HTTPStreamV2.fetch_status_follow_redirect(url)
      assert result_follow_redirect == {:ok, 200}
    end

    test "more redirects than allowed", %{bypass: bypass} do
      url = "http://localhost:#{bypass.port}/"

      # setup a test with 2 successive redirects
      Bypass.expect(bypass, "GET", "/", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("Location", "#{url}1")
        |> Plug.Conn.resp(301, "")
      end)

      Bypass.expect(bypass, "GET", "/1", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("Location", "#{url}2")
        |> Plug.Conn.resp(301, "")
      end)

      Bypass.expect(bypass, "GET", "/2", fn conn ->
        conn
        |> Plug.Conn.resp(404, "")
      end)

      # test with 1 redirect allowed
      assert {:error, "maximum number of redirect reached"} == HTTPStreamV2.fetch_status_follow_redirect(url, 1)

      # test with 2 redirects allowed
      assert {:ok, 404} == HTTPStreamV2.fetch_status_follow_redirect(url, 2)
    end

    test "redirect response, but location header not provided", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/", fn conn ->
        conn
        |> Plug.Conn.resp(301, "Mais ou est le header ?")
      end)

      url = "http://localhost:#{bypass.port}/"
      assert {:ok, 301} == HTTPStreamV2.fetch_status_follow_redirect(url)
    end
  end
end
