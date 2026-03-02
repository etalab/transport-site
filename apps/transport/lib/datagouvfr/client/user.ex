defmodule Datagouvfr.Client.User.Wrapper do
  @moduledoc """
  A wrapper for the User module, useful for testing purposes
  """
  @callback me(Plug.Conn.t() | OAuth2.AccessToken.t()) :: {:error, map()} | {:ok, map()}

  def impl, do: Application.get_env(:transport, :user_impl)
end

defmodule Datagouvfr.Client.User.Dummy do
  @moduledoc """
  A dummy User, to avoid any communication with the Oauth Server.
  """
  @behaviour Datagouvfr.Client.User.Wrapper

  @impl Datagouvfr.Client.User.Wrapper
  def me(_),
    do:
      {:ok,
       %{
         "first_name" => "trotro",
         "last_name" => "rigolo",
         "id" => "user_id_1",
         "email" => "email@example.fr",
         "organizations" => [
           %{
             "slug" => "equipe-transport-data-gouv-fr",
             "name" => "PAN",
             "badges" => [],
             "id" => "5abca8d588ee386ee6ece479",
             "logo" => "https://example.com/pic.jpg",
             "logo_thumbnail" => "https://example.com/pic.small.jpg"
           }
         ]
       }}
end

defmodule Datagouvfr.Client.User do
  @moduledoc """
  An Client to retrieve User information of data.gouv.fr
  """
  alias Datagouvfr.Client.API
  alias Datagouvfr.Client.OAuth, as: Client

  @me_fields ~w(avatar avatar_thumbnail first_name id last_name
                organizations page id uri apikey email)

  @doc """
  Call to GET /api/1/me/
  You can see documentation here: https://doc.data.gouv.fr/api/reference/#/me/
  """
  @spec me(Plug.Conn.t() | OAuth2.AccessToken.t(), [binary()]) ::
          {:error, OAuth2.Error.t()} | {:ok, OAuth2.Response.t()}
  def me(conn_or_token, exclude_fields \\ []) do
    Client.get(conn_or_token, "me", [{"x-fields", xfields(exclude_fields)}])
  end

  @doc """
  Call to GET /api/1/users/:id/
  You can see documentation here: https://www.data.gouv.fr/fr/apidoc/#!/users/get_user
  """
  @spec get(String.t()) :: {atom, any}
  def get(id) do
    "users" |> Path.join(id) |> API.get()
  end

  # private functions

  @spec xfields([binary()]) :: binary()
  defp xfields(exclude_fields) do
    @me_fields
    |> Enum.filter(&(Enum.member?(exclude_fields, &1) == false))
    |> Enum.join(",")
  end
end
