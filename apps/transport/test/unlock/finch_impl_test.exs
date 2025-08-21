defmodule Unlock.FinchImplTests do
  use ExUnit.Case, async: true

  # Since Finch does not provide testing facility, nor
  # redirect support, we need to start an actual server
  # if we want to test our redirect implementation.
  #
  # Moving to Req is advised to get rid of that code.
  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  test "get! with successful redirect", %{bypass: bypass} do
    url = "http://localhost:#{bypass.port}/initial"
    redirected_url = "http://localhost:#{bypass.port}/redirected"

    Bypass.expect(bypass, "GET", "/initial", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", redirected_url)
      |> Plug.Conn.resp(302, "")
    end)

    Bypass.expect(bypass, "GET", "/redirected", fn conn ->
      conn
      |> Plug.Conn.resp(200, "The redirect payload")
    end)

    %{status: status, body: body} = Unlock.HTTP.FinchImpl.get!(url, [], max_redirects: 2)

    assert status == 200
    assert body == "The redirect payload"
  end

  test "get! with too many redirects", %{bypass: bypass} do
    url = "http://localhost:#{bypass.port}/initial"
    redirected_url = "http://localhost:#{bypass.port}/redirected"

    Bypass.expect(bypass, "GET", "/initial", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", redirected_url)
      |> Plug.Conn.resp(302, "")
    end)

    assert_raise RuntimeError, "TooManyRedirects", fn ->
      Unlock.HTTP.FinchImpl.get!(url, [], max_redirects: 0)
    end
  end
end
