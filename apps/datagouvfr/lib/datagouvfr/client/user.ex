defmodule Datagouvfr.Client.User do
  @moduledoc """
  An Client to retrieve User information of data.gouv.fr
  """

  alias Datagouvfr.Client.OAuth, as: Client

  @me_fields ~w(avatar avatar_thumbnail first_name id last_name
                organizations page id uri apikey email)

  @doc """
  Call to GET /api/1/me/
  You can see documentation here: http://www.data.gouv.fr/fr/apidoc/#!/me/
  """
  def me(%Plug.Conn{} = conn, exclude_fields \\ []) do
    Client.get(conn, "me", [{"x-fields", xfields(exclude_fields)}])
  end

  @spec datasets(Plug.Conn.t()) :: {:error, OAuth2.Error.t()} | {:ok, OAuth2.Response.t()}
  def datasets(%Plug.Conn{} = conn) do
    Client.get(conn, Path.join(["me", "datasets"]))
  end

  @spec org_datasets(Plug.Conn.t()) :: {:error, OAuth2.Error.t()} | {:ok, OAuth2.Response.t()}
  def org_datasets(%Plug.Conn{} = conn) do
    Client.get(conn, Path.join(["me", "org_datasets"]))
  end

  #private functions

  defp xfields(exclude_fields) do
    @me_fields
    |> Enum.filter(&Enum.member?(exclude_fields, &1) == false)
    |> Enum.join(",")
  end

end
