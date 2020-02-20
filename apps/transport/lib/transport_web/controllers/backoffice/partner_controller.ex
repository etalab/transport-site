defmodule TransportWeb.Backoffice.PartnerController do
  use TransportWeb, :controller
  alias DB.{Partner, Repo}
  require Logger

  @spec partners(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def partners(%Plug.Conn{} = conn, params) do
    config = make_pagination_config(params)
    partners = Repo.paginate(Partner, page: config.page_number)

    conn
    |> assign(:partners, partners)
    |> render("partners.html")
  end

  @spec post_partner(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def post_partner(%Plug.Conn{} = conn, %{"id" => partner_id, "action" => "delete"}) do
    Partner
    |> Repo.get(partner_id)
    |> Repo.delete()
    |> case do
      {:ok, _} ->
        conn
        |> put_flash(:info, dgettext("backoffice", "Partner deleted"))
        |> redirect(to: backoffice_partner_path(conn, :partners))

      {:error, error} ->
        Logger.error(error)

        conn
        |> put_flash(:error, dgettext("backoffice", "Unable to delete"))
        |> redirect(to: backoffice_partner_path(conn, :partners))
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
    |> redirect(to: backoffice_partner_path(conn, :partners))
  end
end
