defmodule Unlock.Controller do
  @moduledoc """
  The main controller for proxying
  """

  use Phoenix.Controller

  def get(conn, _params) do
    text(conn, "Unlock Proxy")
  end
end
