defmodule TransportWeb.DiscussionController do
  use TransportWeb, :controller
  alias Datagouvfr.Client.Discussions
  require Logger

  @spec post_discussion(Plug.Conn.t(), map) :: Plug.Conn.t()
  def post_discussion(%Plug.Conn{} = conn, %{
        "comment" => comment,
        "dataset_datagouv_id" => dataset_datagouv_id,
        "title" => title,
        "dataset_slug" => dataset_slug
      }) do
    conn
    |> Discussions.post(dataset_datagouv_id, title, comment)
    |> case do
      {:ok, _} ->
        put_flash(conn, :info, dgettext("page-dataset-details", "New discussion started"))

      {:error, error} ->
        Logger.error("When starting a new discussion: #{inspect(error)}")
        put_flash(conn, :error, dgettext("page-dataset-details", "Unable to start a new discussion"))
    end
    |> redirect(to: dataset_path(conn, :details, dataset_slug))
  end

  @spec post_answer(Plug.Conn.t(), map) :: Plug.Conn.t()
  def post_answer(
        %Plug.Conn{} = conn,
        %{"discussion_id" => discussion_id, "comment" => comment, "dataset_slug" => dataset_slug} = params
      ) do
    conn
    |> Discussions.post(discussion_id, comment, close: Map.has_key?(params, "anwser_and_close"))
    |> case do
      {:ok, _} ->
        conn
        |> put_flash(:info, dgettext("page-dataset-details", "Answer published"))

      {:error, error} ->
        Logger.error("When publishing an answer: #{inspect(error)}")

        conn
        |> put_flash(:error, dgettext("page-dataset-details", "Unable to publish the answer"))
    end
    |> redirect(to: dataset_path(conn, :details, dataset_slug))
  end
end
