defmodule Unlock.ErrorView do
  def render("500.html", _assigns) do
    "Internal Server Error"
  end
end
