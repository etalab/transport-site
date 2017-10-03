defmodule Transport.Datagouvfr.Client do
  @moduledoc """
  An API client for data.gouv.fr
  """

  use HTTPoison.Base
  alias Transport.Datagouvfr.Authentication

  @base_url Application.get_env(:oauth2, Authentication)[:site] |> Path.join("/api/1/")
  @apikey Application.get_env(:oauth2, Authentication)[:apikey]

  @doc """
  Call to GET /organizations/
  You can see documentation here: http://www.data.gouv.fr/fr/apidoc/#!/organizations/list_organizations
  """
  @spec organizations :: {atom, [map]}
  def organizations do
    organizations(%{})
  end

  @doc """
  Call to GET /organizations/
  You can see documentation here: http://www.data.gouv.fr/fr/apidoc/#!/organizations/list_organizations
  """
  @spec organizations(map) :: {atom, [map]}
  def organizations(params) do
    headers = []

    case get("organizations", headers, params: params) do
      {:ok, response} -> response.body
      {:error, error} -> error
    end
  end

  @doc """
  Call to GET /organizations/{slug}/
  You can see documentation here: http://www.data.gouv.fr/fr/apslugoc/#!/organizations/get_organization
  """
  @spec organization(String.t) :: {atom, map}
  def organization(slug) do
    case get(Path.join("organizations", slug)) do
      {:ok, response} -> response.body
      {:error, error} -> {:error, error}
    end
  end

  def organization({:ok, response}, :with_membership) do
    url = Path.join(["organizations", response["slug"], "membership"])
    headers = [{"X-API-KEY", @apikey}]
    case get(url, headers) do
      {:ok, %{body: {:ok, r}}} -> {:ok, Map.put(response, "membership", r)}
      {:ok, %{body: {:error, e}}} -> {:error, e}
      {:error, error} -> {:error, error}
    end
  end
  def organization({:error, error}, :with_membership) do
    {:error, error}
  end
  @doc """
  Call to GET /organizations/{slug}/ and add result of /organizations/{slug}/membership/
  You can see documentation here: http://www.data.gouv.fr/fr/apslugoc/#!/organizations/get_organization
  """
  @spec organization(String.t, atom) :: {atom, [map]}
  def organization(slug, :with_membership) do
    organization(organization(slug), :with_membership)
  end

  @doc """
  Call to PUT /organizations/{slug}/membership/
  API documentation: http://www.data.gouv.fr/fr/apidoc/#!/organizations/post_membership_request_api
  """
  @spec request_organization_membership(String.t, String.t) :: {atom, [map]}
  def request_organization_membership(organization_slug, current_user_id) do
    url = Path.join(["organizations", organization_slug, "membership"])
    headers = [{"Content-type", "application/json"},
               {"X-API-KEY", @apikey}]
    body = Poison.encode!(%{"comment": "tranport.data.gouv.fr request",
                            "user": %{"id": current_user_id}})
    case put(url, body, headers) do
      {:ok, response} -> response.body
      {:error, error} -> error
    end
  end

  # extended functions of HTTPoison

  def process_response_body(body) do
    body
    |> Poison.decode
  end

  def process_url(path) do
    @base_url
    |> Path.join(path)
    |> URI.parse
    |> add_trailing_slash
  end

  # private

  defp add_trailing_slash(uri) when is_map(uri) do
    %URI{uri | path: add_trailing_slash(uri.path)}
    |> to_string
  end

  defp add_trailing_slash(path) do
    case path |> String.slice(-1..-1) do
      "/" -> path
      _ -> path <> "/"
    end
  end
end
