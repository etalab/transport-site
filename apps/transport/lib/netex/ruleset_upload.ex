defmodule Transport.EnRouteChouetteValidRulesetsClient.Wrapper do
  @moduledoc """
  API client for Chouette Valid rulesets management.
  Documentation: https://enroute.atlassian.net/wiki/spaces/PUBLIC/pages/2761687047/Sprint+123#Manage-rulesets-by-API
  """

  @callback post_ruleset(definition :: binary(), name :: binary(), slug :: binary()) ::
              :ok
              | {:error, binary()}

  def impl, do: Application.get_env(:transport, :enroute_rulesets_client)
end

defmodule Transport.EnRouteChouetteValidRulesetsClient do
  @moduledoc """
  Implementation of the enRoute Chouette Valid rulesets management API client.
  """
  @behaviour Transport.EnRouteChouetteValidRulesetsClient.Wrapper

  @base_url "https://chouette-valid.enroute.mobi/api/rulesets"

  @impl Transport.EnRouteChouetteValidRulesetsClient.Wrapper
  def post_ruleset(definition, name, slug) do
    body =
      %{
        ruleset: %{
          name: name,
          slug: slug,
          definition: definition
        }
      }
      |> JSON.encode!()

    headers = [{"Accept", "application/json"}] ++ auth_headers()

    case http_client().post(@base_url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: _}} ->
        :ok

      {:ok, %HTTPoison.Response{status_code: sc, body: body}} ->
        {:error, "Bad API response: Status code: #{sc}, response body: #{body}"}

      {:ok, _unsupported} ->
        {:error, "Unsupported response type"}

      {:error, e} ->
        {:error, Exception.message(e)}
    end
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()

  defp auth_headers do
    [{"authorization", "Token token=#{Application.fetch_env!(:transport, :enroute_rulesets_token)}"}]
  end
end
