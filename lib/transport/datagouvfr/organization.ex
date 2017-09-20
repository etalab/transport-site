defmodule Transport.Datagouvfr.Organization do
  @moduledoc """
  An API client for data.gouv.fr's organizations
  """

  alias Transport.Datagouvfr.Authentication

  @base_url Application.get_env(:oauth2, Authentication)[:site] |> Path.join("/api/1/")

  @doc """
  Retrive a lot of organizations.
  """
  @spec all :: {atom(), [%{}]}
  def all do
    search("")
  end

  @doc """
  Searches for organizations matching term.
  """
  @spec search(String.t) :: {atom(), [%{}]}
  def search(term) do
    url     = build_url("organizations")
    headers = []
    params  = %{q: term}

    case HTTPoison.get(url, headers, params: params) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body |> Poison.decode! |> Map.get("data")}
      {:_, error} ->
        {:error, error}
    end
  end

  # private

  defp build_url(path) do
    @base_url
    |> Path.join(path)
    |> URI.parse
    |> add_trailing_slash
  end

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
