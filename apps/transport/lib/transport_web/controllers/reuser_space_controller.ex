defmodule TransportWeb.ReuserSpaceController do
  use TransportWeb, :controller
  import Ecto.Query

  def espace_reutilisateur(%Plug.Conn{assigns: %{current_user: %{"id" => datagouv_user_id}}} = conn, _) do
    contact = DB.Repo.get_by!(DB.Contact, datagouv_user_id: datagouv_user_id)
    followed_datasets_ids = contact |> Ecto.assoc(:followed_datasets) |> select([d], d.id) |> DB.Repo.all()

    conn
    |> assign(:contact, contact)
    |> assign(:followed_datasets_ids, followed_datasets_ids)
    |> render("index.html")
  end

  def datasets_edit(%Plug.Conn{} = conn, _), do: text(conn, "Coming later")
end
