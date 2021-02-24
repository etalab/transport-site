defmodule TransportWeb.ErrorView do
  use TransportWeb, :view

  def render("500.html", assigns) do
    render(__MODULE__, "internal_server_error.html", assigns)
  end

  def render("400.html", assigns) do
    assigns =
      assigns
      |> Map.put(:status_message, dgettext("errors", "400: Bad Request"))

    render(__MODULE__, "400_family_errors.html", assigns)
  end

  def render("404.html", assigns) do
    assigns = assigns |> Map.put(:status_message, dgettext("errors", "404: Page not available"))
    render(__MODULE__, "400_family_errors.html", assigns)
  end
end
