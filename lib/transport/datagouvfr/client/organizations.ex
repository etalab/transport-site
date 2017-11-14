defmodule Transport.Datagouvfr.Client.Organizations do
  @moduledoc """
  An API client for data.gouv.fr organizations
  """

  import Transport.Datagouvfr.Client, only: [get_request: 2, get_request: 4,
                                             post_request: 3]
  import TransportWeb.Gettext
  alias Transport.Datagouvfr.Client.Datasets

  @endpoint "organizations"

  def get(%Plug.Conn{} = conn) do
    get(conn, %{})
  end

  @spec get(%Plug.Conn{}, map) :: {atom, [map]}
  @doc """
  Call to GET /organizations/
  You can see documentation here: http://www.data.gouv.fr/fr/apidoc/#!/organizations/list_organizations
  """
  @spec get(%Plug.Conn{}, map) :: {atom, [map]}
  def get(%Plug.Conn{} = conn, params) when is_map(params) do
    conn
    |> get_request(@endpoint, [], params: params)
  end

  @doc """
  Call to GET /api/1/organizations/:slug/
  You can see documentation here: http://www.data.gouv.fr/fr/apidoc/#!/organizations/get_organization
  """
  @spec get(%Plug.Conn{}, String.t) :: {atom, [map]}
  def get(%Plug.Conn{} = conn, slug) do
    conn
    |> get_request(Path.join(@endpoint, slug))
  end

  @doc """
  Call to GET /api/1/organizations/:slug/
  And add datasets to it.
  """
  @spec get(%Plug.Conn{}, String.t, atom) :: {atom, map}
  def get(%Plug.Conn{} = conn, slug, :with_datasets) do
    conn
    |> get(get(conn, slug), slug, :with_datasets)
  end

  def get(%Plug.Conn{} = conn, {:ok, body}, slug, :with_datasets) do
    case Datasets.get(conn, %{:organization => slug}) do
      {:ok, body_datasets} -> {:ok, Map.put(body, "datasets", body_datasets)}
      {:error, error} -> {:error, error}
    end
  end

  def get(%Plug.Conn{} = _, {:error, error}, _, _) do
    {:error, error}
  end

  def post(%Plug.Conn{} = conn, %{"name"        => name,
                                  "description" => description} = params)
    when name != "" and description != "" do
    conn
    |> post_request("/organizations/", params)
  end

  def post(%Plug.Conn{} = _conn, params) do
    errors =
      if not Map.has_key?(params, "name") or params["name"] == "" do
        [dgettext("user", "You need to provide an organisation name")]
      else
        []
      end
    errors =
      if not Map.has_key?(params, "description") or params["description"] == "" do
        errors ++ [dgettext("user", "You need to provide an organisation description")]
      else
        errors
      end
    {:validation_error, errors}
  end
end
