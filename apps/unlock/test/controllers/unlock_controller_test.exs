defmodule Unlock.ControllerTest do
  use ExUnit.Case
  use Plug.Test
  import Phoenix.ConnTest
  @endpoint Unlock.Endpoint

  import Mox
  setup :verify_on_exit!
  test "GET /" do
    output =
      build_conn()
      |> get("/")
      |> text_response(200)

    assert output == "Unlock Proxy"
  end
end
