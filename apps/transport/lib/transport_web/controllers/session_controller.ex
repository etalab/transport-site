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
           |> put_session(:datagouv_token, token)
           |> assign(:datagouv_token, token),
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

      # First login on the platform.
      # - we created the contact on the backoffice: fill `datagouv_user_id`
      # - create the contact for the first time using OAuth details
      nil ->
        contact = find_contact_by_email_or_create(user_params)
        maybe_promote_producer_space(contact)
        contact
    end
    |> DB.Contact.changeset(%{last_login_at: DateTime.utc_now(), organizations: organizations})
    |> DB.Repo.update!()
  end

  defp maybe_promote_producer_space(%DB.Contact{id: contact_id}) do
    # Schedule the job in a few seconds to make sure the record has been
    # inserted and we properly updated organizations.
    # The job is scheduled for all contacts when they login for the first time
    # and does stuff only if the contact is a producer.
    %{contact_id: contact_id} |> Transport.Jobs.PromoteProducerSpaceJob.new(schedule_in: 5) |> Oban.insert!()
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
          email: email,
          creation_source: :datagouv_oauth_login
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
    conn
    |> put_session(:current_user, user_params_for_session(user_params))
    |> TransportWeb.Session.set_is_producer(user_params)
    |> TransportWeb.Session.set_is_admin(user_params)
  end

  defp user_params_for_session(%{} = params) do
    # Remove the list of `organizations` from the final map: it's already stored in the database
    # and maintained up-to-date by `Transport.Jobs.UpdateContactsJob`
    # and it can be too big to be stored in a cookie
    Map.delete(params, "organizations")
  end

  defp get_redirect_path(%Plug.Conn{} = conn) do
    case get_session(conn, :redirect_path) do
      nil -> "/"
      path -> path
    end
  end
end
