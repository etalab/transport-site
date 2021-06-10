defmodule Unlock.ControllerTest do
  use ExUnit.Case
  use Plug.Test
  import Phoenix.ConnTest
  @endpoint Unlock.Endpoint

  import Mox
  setup :verify_on_exit!

  # TODO: persist config in DB for reliability during GitHub outages

  test "GET /" do
    output =
      build_conn()
      |> get("/")
      |> text_response(200)

    assert output == "Unlock Proxy"
  end

  def setup_proxy_config(config) do
    Unlock.Config.Fetcher.Mock
    |> stub(:fetch_config!, fn() -> config end)
  end

  describe "GET /resource/:slug" do
    test "handles a regular read" do
      # TODO: create clean struct for item
      setup_proxy_config(%{"some-configure-slug" => stuff})

      build_conn()
      |> get("/resource/some-configured-slug")
    end

    test "handles 404"
    test "handles caching"
    test "supports reloading"
    test "handles remote error"
    test "handles proxy error"
  end
end
