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
end
