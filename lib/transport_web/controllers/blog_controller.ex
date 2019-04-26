defmodule TransportWeb.BlogController do
  use TransportWeb, :controller

  def page(conn, %{"page" => page}), do: render conn, "article.html", page: page <> ".html"

end
