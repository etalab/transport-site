defmodule TransportWeb.Backoffice.PartnerController do
  use TransportWeb, :controller

  alias Transport.{Repo, Partner}
  require Logger


  def partners(%Plug.Conn{} = conn, params) do
    config = make_pagination_config(params)
    partners = Repo.paginate(Partner, page: config.page_number)

    conn
    |> assign(:partners, partners)
    |> render("partners.html")
  end

  def post_partner(%Plug.Conn{} = conn, %{"id" => partner_id, "action" => "delete"}) do
    partner = Repo.get(Partner, partner_id)

    case Repo.delete(partner) do
      {:ok, _} ->
        conn
        |> put_flash(:info, dgettext("backoffice", "Partner deleted"))
        |> redirect(to: backoffice_page_path(conn, :partners))
      {:error, error} ->
        Logger.error(error)
        conn
        |> put_flash(:error, dgettext("backoffice", "Unable to delete"))
        |> redirect(to: backoffice_page_path(conn, :partners))
    end
  end

  def post_partner(%Plug.Conn{} = conn, %{"partner_url" => partner_url}) do
    with true <- Partner.is_datagouv_partner_url?(partner_url),
         {:ok, partner} <- Partner.from_url(partner_url),
         {:ok, _} <- Repo.insert(partner) do
      put_flash(conn, :info, dgettext("backoffice", "Partner added"))
    else
      false ->
        put_flash(conn, :error, dgettext("backoffice", "This has to be an organization or a user"))
      {:error, error} ->
        Logger.error(error)
        put_flash(conn, :error, dgettext("backoffice", "Unable to insert partner in database"))
    end
    |> redirect(to: backoffice_page_path(conn, :partners))
  end

end
