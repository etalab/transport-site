defmodule Unlock.ControllerTest do
  use ExUnit.Case
  use Plug.Test
  import Phoenix.ConnTest
  @endpoint Unlock.Endpoint

  test "/" do
    build_conn()
    |> get("/")
    |> text_response(200)
  end
end
