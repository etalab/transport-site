defmodule TransportWeb.DiscussionController do
  use TransportWeb, :controller

  alias Transport.Datagouvfr.Client.Discussions

  def post_discussion_id(conn, %{"id_" => id_, "comment" => comment}) do
    conn
    |> Discussions.post(id_, comment)
    |> case do
      {:ok, _} -> render conn, "ok.json"
      {:error, error} -> render conn, "error.json", error
    end
  end

  def post_discussion(conn, %{"comment" => comment, "id_" => id_, "title" => title}) do
    conn
    |> Discussions.post(id_, comment, title)
    |> case do
      {:ok, _} -> render conn, "ok.json"
      {:error, error} -> render conn, "error.json", error
    end
  end
end
