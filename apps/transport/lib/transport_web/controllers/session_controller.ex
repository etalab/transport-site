defmodule TransportWeb.SessionController do
  @moduledoc """
  Session management for transport.
  """
  use TransportWeb, :controller
  alias Datagouvfr.Authentication
  import Ecto.Query
  require Logger

  def new(conn, _) do
    redirect(conn, external: Authentication.authorize_url())
  end

  def create(conn, %{"code" => code}) do
    authentication_module = Datagouvfr.Authentication.Wrapper.impl()
    user_module = Datagouvfr.Client.User.Wrapper.impl()

    with %{token: token} <- authentication_module.get_token!(code: code),
         conn <-
           conn
           |> put_session(:token, token)
           |> assign(:token, token),
         {:ok, user} <- user_module.me(conn) do
      user_params = user_params(user)
      find_or_create_contact(user_params)

      conn
      |> save_current_user(user_params)
      |> redirect(to: get_redirect_path(conn))
      |> halt()
    else
      {:error, error} ->
        Logger.error(error)

        conn
        |> put_flash(:error, dgettext("alert", "An error occured, please try again"))
        |> redirect(to: session_path(conn, :new))
        |> halt()
    end
  end

  def create(conn, %{"error" => error, "error_description" => description}) do
    Logger.error("error while creating the session: #{error} - #{description}")

    conn
    |> put_flash(:error, dgettext("alert", "An error occured, please try again"))
    |> redirect(to: session_path(conn, :new))
    |> halt()
  end

  def delete(%Plug.Conn{} = conn, _) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: get_redirect_path(conn))
    |> halt()
  end

  def find_or_create_contact(
        %{
          "id" => user_id,
          "first_name" => first_name,
          "last_name" => last_name,
          "email" => email,
          "organizations" => organizations
        } = user_params
      ) do
    DB.Contact
    |> DB.Repo.get_by(datagouv_user_id: user_id)
    |> case do
      %DB.Contact{mailing_list_title: nil} = contact ->
        contact
        |> DB.Contact.changeset(%{
          first_name: first_name,
          last_name: last_name,
          email: email
        })
        |> DB.Repo.update!()

      %DB.Contact{mailing_list_title: mailing_list_title} = contact when mailing_list_title != nil ->
        contact
        |> DB.Contact.changeset(%{email: email})
        |> DB.Repo.update!()

      nil ->
        find_contact_by_email_or_create(user_params)
    end
    |> DB.Contact.changeset(%{last_login_at: DateTime.utc_now(), organizations: organizations})
    |> DB.Repo.update!()
  end

  defp find_contact_by_email_or_create(%{
         "id" => user_id,
         "first_name" => first_name,
         "last_name" => last_name,
         "email" => email
       }) do
    case DB.Repo.get_by(DB.Contact, email_hash: String.downcase(email)) do
      %DB.Contact{mailing_list_title: nil} = contact ->
        contact
        |> DB.Contact.changeset(%{
          datagouv_user_id: user_id,
          first_name: first_name,
          last_name: last_name
        })
        |> DB.Repo.update!()

      %DB.Contact{mailing_list_title: mailing_list_title} = contact when mailing_list_title != nil ->
        contact
        |> DB.Contact.changeset(%{datagouv_user_id: user_id})
        |> DB.Repo.update!()

      nil ->
        %{
          datagouv_user_id: user_id,
          first_name: first_name,
          last_name: last_name,
          email: email
        }
        |> DB.Contact.insert!()
    end
  end

  defp user_params(%{} = user) do
    Map.take(
      user,
      ["id", "apikey", "email", "first_name", "last_name", "avatar_thumbnail", "organizations"]
    )
  end

  def save_current_user(%Plug.Conn{} = conn, %{} = user_params) do
    conn |> put_session(:current_user, user_params_for_session(user_params))
  end

  def user_params_for_session(%{} = params) do
    params
    # Remove the list of `organizations` from the final map: it's already stored in the database
    # and maintained up-to-date by `Transport.Jobs.UpdateContactsJob`
    # and it can be too big to be stored in a cookie
    |> Map.delete("organizations")
    # - `is_admin` is needed to check permissions
    # - `is_producer` is used to get access to the "Espace producteur"
    |> Map.merge(%{"is_producer" => is_producer?(params), "is_admin" => is_admin?(params)})
  end

  @doc """
  Are you a data producer?
  You're a data producer if you're a member of an organization with an active dataset
  on transport.data.gouv.fr.
  This is set when you log in, we can refresh this field more often in the future.
  """
  def is_producer?(%{"organizations" => orgs}) do
    org_ids = Enum.map(orgs, & &1["id"])

    DB.Dataset.base_query() |> where([dataset: d], d.organization_id in ^org_ids) |> DB.Repo.exists?()
  end

  @doc """
  Are you a transport.data.gouv.fr admin?
  You're an admin if you're a member of the PAN organization on data.gouv.fr.

  iex> is_admin?(%{"organizations" => [%{"slug" => "equipe-transport-data-gouv-fr"}, %{"slug" => "foo"}]})
  true
  iex> is_admin?(%{"organizations" => [%{"slug" => "foo"}]})
  false
  iex> is_admin?(%{"organizations" => []})
  false
  """
  def is_admin?(%{"organizations" => orgs}) do
    Enum.any?(orgs, &(&1["slug"] == "equipe-transport-data-gouv-fr"))
  end

  defp get_redirect_path(%Plug.Conn{} = conn) do
    case get_session(conn, :redirect_path) do
      nil -> "/"
      path -> path
    end
  end
end
