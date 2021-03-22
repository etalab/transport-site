defmodule Unlock.Controller do
  @moduledoc """
  The main controller for proxying
  """

  use Phoenix.Controller

  def index(conn, _params) do
    text(conn, "Unlock Proxy")
  end
end
