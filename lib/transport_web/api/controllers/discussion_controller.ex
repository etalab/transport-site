defmodule TransportWeb.API.DiscussionController do
  use TransportWeb, :controller

  alias Transport.Datagouvfr.Client.Discussions

  def post_discussion(conn, %{"comment" => comment,
                              "id_" => id_,
                              "title" => title,
                              "extras" => extras}) do
    conn
    |> Discussions.post(id_, title, comment, extras)
    |> case do
      {:ok, body} -> render(conn, data: body)
      {:error, error} -> render(conn, errors: [error])
    end
  end

  def post_discussion(conn, %{"comment" => _comment,
                              "id_" => _id_,
                              "title" => _title} = params) do
    post_discussion(conn, Map.put(params, "extras", nil))
  end

  def post_discussion(conn, %{"id_" => id_, "comment" => comment}) do
    conn
    |> Discussions.post(id_, comment)
    |> case do
      {:ok, body} -> render(conn, data: body)
      {:error, error} -> render(conn, errors: [error])
    end
  end
end
