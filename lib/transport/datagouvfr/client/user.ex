defmodule Transport.Datagouvfr.Client.User do
  @moduledoc """
  An Client to retrieve User information of data.gouv.fr
  """

  import Transport.Datagouvfr.Client, only: [get_request: 3]

  @me_fields ~w(avatar avatar_thumbnail first_name id last_name
                organizations page slug uri apikey email)

  @doc """
  Call to GET /api/1/me/
  You can see documentation here: http://www.data.gouv.fr/fr/apidoc/#!/me/
  """
  def me(%Plug.Conn{} = conn, exclude_fields \\ []) do
    conn
    |> get_request("me", [{"x-fields", xfields(exclude_fields)}])
  end

  #private functions

  defp xfields(exclude_fields) do
    @me_fields
    |> Enum.filter(&Enum.member?(exclude_fields, &1) == false)
    |> Enum.join(",")
  end

end
