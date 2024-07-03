defmodule TransportWeb.Session do
  @moduledoc """
  Web session getters and setters.
  """
  import Ecto.Query
  import Plug.Conn

  @is_admin_key_name "is_admin"
  @is_producer_key_name "is_producer"

  @doc """
  Are you a data producer?

  You're a data producer if you're a member of an organization with an active dataset
  on transport.data.gouv.fr.
  This is set when you log in and refreshed when you visit your "Espace producteur".
  """
  @spec set_is_producer(Plug.Conn.t(), map() | [DB.Dataset.t()]) :: Plug.Conn.t()
  def set_is_producer(%Plug.Conn{} = conn, %{"organizations" => _} = params) do
    set_session_attribute_attribute(conn, @is_producer_key_name, producer?(params))
  end

  def set_is_producer(%Plug.Conn{} = conn, datasets_for_user) when is_list(datasets_for_user) do
    is_producer = not Enum.empty?(datasets_for_user)
    set_session_attribute_attribute(conn, @is_producer_key_name, is_producer)
  end

  @doc """
  Are you a transport.data.gouv.fr admin?
  You're an admin if you're a member of the PAN organization on data.gouv.fr.
  """
  def set_is_admin(%Plug.Conn{} = conn, %{"organizations" => _} = params) do
    set_session_attribute_attribute(conn, @is_admin_key_name, admin?(params))
  end

  def admin?(%{"organizations" => orgs}) do
    Enum.any?(orgs, &(&1["slug"] == "equipe-transport-data-gouv-fr"))
  end

  def admin?(%Plug.Conn{} = conn) do
    conn |> current_user() |> Map.get(@is_admin_key_name, false)
  end

  def admin?(%Phoenix.LiveView.Socket{assigns: %{current_user: current_user}}) do
    Map.get(current_user, @is_admin_key_name, false)
  end

  def producer?(%Plug.Conn{} = conn) do
    conn |> current_user() |> Map.get(@is_producer_key_name, false)
  end

  def producer?(%DB.Contact{organizations: organizations}) do
    producer?(%{"organizations" => organizations})
  end

  def producer?(%{"organizations" => orgs}) do
    org_ids = Enum.map(orgs, & &1["id"])
    DB.Dataset.base_query() |> where([dataset: d], d.organization_id in ^org_ids) |> DB.Repo.exists?()
  end

  @doc """
  A temporary helper method to determine if we should display "reuser space features".
  Convenient method to find various entrypoints in the codebase:
  - links and buttons to the reuser space
  - follow dataset hearts (search results, dataset pages)
  - reuser space

  Enable it for everybody but keep a "kill switch" to disable it quickly
  by setting an environment variable and rebooting the app.

  transport.data.gouv.fr admins get access no matter what.
  """
  def display_reuser_space?(%Plug.Conn{} = conn) do
    feature_disabled = Application.fetch_env!(:transport, :disable_reuser_space)
    admin?(conn) or not feature_disabled
  end

  @spec set_session_attribute_attribute(Plug.Conn.t(), binary(), boolean()) :: Plug.Conn.t()
  defp set_session_attribute_attribute(%Plug.Conn{} = conn, key, value) do
    current_user = current_user(conn)
    conn |> put_session(:current_user, Map.put(current_user, key, value))
  end

  defp current_user(%Plug.Conn{} = conn), do: get_session(conn, :current_user, %{})
end
