defmodule Transport.Datagouvfr.Client do
  @moduledoc """
  An API client for data.gouv.fr
  """

  use HTTPoison.Base
  alias Transport.Datagouvfr.Authentication

  @base_url Application.get_env(:oauth2, Authentication)[:site] |> Path.join("/api/1/")

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
  @spec organization(map) :: {atom, map}
  def organization(slug) do
    case get(Path.join("organizations", slug)) do
      {:ok, response} -> response.body
      {:error, error} -> {:error, error}
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
