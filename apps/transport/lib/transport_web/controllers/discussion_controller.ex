defmodule TransportWeb.DiscussionController do
  use TransportWeb, :controller
  alias Datagouvfr.Client.Discussions.Wrapper, as: Discussions
  require Logger

  plug(:assign_dataset)
  plug(:assign_current_contact)

  @spec post_discussion(Plug.Conn.t(), map) :: Plug.Conn.t()
  def post_discussion(%Plug.Conn{} = conn, %{
        "comment" => comment,
        "dataset_datagouv_id" => dataset_datagouv_id,
        "title" => title,
        "dataset_slug" => dataset_slug
      }) do
    DB.FeatureUsage.insert!(
      :post_discussion,
      get_in(conn.assigns.current_contact.id),
      %{dataset_id: conn.assigns.dataset.id}
    )

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
    DB.FeatureUsage.insert!(
      :post_comment,
      get_in(conn.assigns.current_contact.id),
      %{dataset_id: conn.assigns.dataset.id, close: Map.has_key?(params, "answer_and_close")}
    )

    conn
    |> Discussions.post(discussion_id, comment, close: Map.has_key?(params, "answer_and_close"))
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

  defp assign_dataset(%Plug.Conn{params: %{"dataset_slug" => dataset_slug}} = conn, _options) do
    assign(
      conn,
      :dataset,
      DB.Repo.get_by(DB.Dataset, slug: dataset_slug)
    )
  end

  defp assign_current_contact(%Plug.Conn{assigns: %{current_user: current_user}} = conn, _options) do
    current_contact =
      if is_nil(current_user) do
        nil
      else
        DB.Contact
        |> DB.Repo.get_by!(datagouv_user_id: Map.fetch!(current_user, "id"))
        |> DB.Repo.preload(:default_tokens)
      end

    assign(conn, :current_contact, current_contact)
  end
end
