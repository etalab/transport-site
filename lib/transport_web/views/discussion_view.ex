defmodule TransportWeb.DiscussionView do
  use TransportWeb, :view

  def render("ok.json", _) do
    %{ok: "ok"}
  end

  def render("error.json", error) do
    %{error: error}
  end
end
