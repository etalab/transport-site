defmodule TransportWeb.SessionController do
  @moduledoc """
  Session management for transport.
  """

  use TransportWeb, :controller
  alias Datagouvfr.Authentication
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
      |> put_session(:current_user, user_params)
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
        %{"id" => user_id, "first_name" => first_name, "last_name" => last_name, "email" => email} = user_params
      ) do
    DB.Contact
    |> DB.Repo.get_by(datagouv_user_id: user_id)
    |> case do
      %DB.Contact{mailing_list_title: nil} = contact ->
        contact
        |> DB.Contact.changeset(%{first_name: first_name, last_name: last_name, email: email})
        |> DB.Repo.update!()

      %DB.Contact{mailing_list_title: mailing_list_title} = contact when mailing_list_title != nil ->
        contact |> DB.Contact.changeset(%{email: email}) |> DB.Repo.update!()

      nil ->
        find_contact_by_email_or_create(user_params)
    end
    |> DB.Contact.changeset(%{last_login_at: DateTime.utc_now()})
    |> DB.Repo.update!()
  end

  defp find_contact_by_email_or_create(%{
         "id" => user_id,
         "first_name" => first_name,
         "last_name" => last_name,
         "email" => email,
         "organizations" => organizations
       }) do
    case DB.Repo.get_by(DB.Contact, email_hash: email) do
      %DB.Contact{mailing_list_title: nil} = contact ->
        contact
        |> DB.Contact.changeset(%{datagouv_user_id: user_id, first_name: first_name, last_name: last_name})
        |> DB.Repo.update!()

      %DB.Contact{mailing_list_title: mailing_list_title} = contact when mailing_list_title != nil ->
        contact |> DB.Contact.changeset(%{datagouv_user_id: user_id}) |> DB.Repo.update!()

      nil ->
        %{
          datagouv_user_id: user_id,
          first_name: first_name,
          last_name: last_name,
          email: email,
          organization: organization_name(organizations)
        }
        |> DB.Contact.insert!()
    end
  end

  @doc """
  The best organization name possible to use when creating a contact.

  iex> organization_name([])
  "Inconnue"
  iex> organization_name([%{"name" => "1"}, %{"name" => "2"}])
  "1"
  """
  def organization_name([]), do: "Inconnue"
  def organization_name(orgs), do: orgs |> List.first() |> Map.fetch!("name")

  defp user_params(%{} = user) do
    params =
      Map.take(
        user,
        ["id", "apikey", "email", "first_name", "last_name", "avatar_thumbnail", "organizations"]
      )

    filtered_organizations =
      Enum.filter(
        Map.get(params, "organizations", []),
        fn org -> org["slug"] == "equipe-transport-data-gouv-fr" end
      )

    Map.put(params, "organizations", filtered_organizations)
  end

  defp get_redirect_path(%Plug.Conn{} = conn) do
    case get_session(conn, :redirect_path) do
      nil -> "/"
      path -> path
    end
  end
end
