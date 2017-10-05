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
  Call to GET /api/1/me/
  You can see documentation here: http://www.data.gouv.fr/fr/apidoc/#!/me/
  """
  @spec me(map) :: {atom, [map]}
  def me(%{:apikey => apikey}) do
    case get("me",
             [{"X-API-KEY", apikey}],
             [timeout: 50_000, recv_timeout: 50_000]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> body
      {:ok, %HTTPoison.Response{status_code: _, body: body}} -> {:error, body}
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
