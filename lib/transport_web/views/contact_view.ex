defmodule TransportWeb.ContactView do
  use TransportWeb, :view

  def render("send_mail.json", %{body: body}) do
    %{body: body}
  end
end
