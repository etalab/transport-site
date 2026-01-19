defmodule Transport.EnRoute.ChouetteValidRulesetsClient.Wrapper do
  @moduledoc """
  API client for Chouette Valid rulesets management.
  Documentation: https://enroute.atlassian.net/wiki/spaces/PUBLIC/pages/2761687047/Sprint+123#Manage-rulesets-by-API
  """
  alias Transport.EnRoute.ChouetteValidRulesetsClient.Slugs

  @type ruleset_id :: binary

  @callback list_rulesets() :: list()

  @callback get_ruleset(slug :: Slugs.slug()) :: {:ok, map()} | {:error, binary()}

  @callback create_ruleset(definition :: binary(), name :: binary(), slug :: Slugs.slug()) ::
              {:ok, ruleset_id()}
              | {:error, binary()}

  @callback update_ruleset(definition :: binary(), name :: binary(), slug :: Slugs.slug()) ::
              {:ok, ruleset_id()}
              | {:error, binary()}

  @callback delete_ruleset(ruleset_id :: ruleset_id()) :: :ok | {:error, binary()}

  @spec list_versions(slug :: Slugs.slug()) :: list()
  def list_versions(slug) do
    reference_slug =
      if Slugs.versioned_slug?(slug) do
        slug
      else
        "#{slug}:1"
      end

    impl().list_rulesets()
    |> Enum.filter(fn %{"slug" => version_slug} -> Slugs.sibling_slugs?(reference_slug, version_slug) end)
  end

  @spec find_ruleset_id(slug :: Slugs.slug()) :: ruleset_id() | nil
  def find_ruleset_id(expected_slug) do
    case impl().get_ruleset(expected_slug) do
      {:ok, ruleset} -> ruleset["id"]
      {:error, _} -> nil
    end
  end

  def impl, do: Application.get_env(:transport, :enroute_rulesets_client)
end

defmodule Transport.EnRoute.ChouetteValidRulesetsClient do
  @moduledoc """
  Implementation of the enRoute Chouette Valid rulesets management API client.
  """
  @behaviour Transport.EnRoute.ChouetteValidRulesetsClient.Wrapper

  @base_url "https://chouette-valid.enroute.mobi/api/rulesets"

  @impl Transport.EnRoute.ChouetteValidRulesetsClient.Wrapper
  def list_rulesets do
    http_client().get!(base_request()).body
  end

  @impl Transport.EnRoute.ChouetteValidRulesetsClient.Wrapper
  def get_ruleset(slug) do
    case http_client().get(base_request(), url: "/#{slug}") do
      {:ok, resp} when resp.status in 200..299 -> {:ok, resp.body}
      {:ok, resp} -> {:error, "Bad API response: Status code: #{resp.status}"}
      {:error, e} -> {:error, Exception.message(e)}
    end
  end

  @impl Transport.EnRoute.ChouetteValidRulesetsClient.Wrapper
  def create_ruleset(definition, name, slug) do
    upsert_ruleset(:post, "", definition, name, slug)
  end

  @impl Transport.EnRoute.ChouetteValidRulesetsClient.Wrapper
  def update_ruleset(definition, name, slug) do
    upsert_ruleset(:put, "/#{slug}", definition, name, slug)
  end

  @impl Transport.EnRoute.ChouetteValidRulesetsClient.Wrapper
  def delete_ruleset(ruleset_id) do
    case http_client().delete(base_request(), url: "/#{ruleset_id}.json") do
      {:ok, resp} when resp.status in 200..299 -> :ok
      {:ok, resp} -> {:error, "Bad API response: Status code: #{resp.status}"}
      {:error, e} -> {:error, Exception.message(e)}
    end
  end

  defp upsert_ruleset(method, path, definition, name, slug) do
    body =
      %{
        ruleset: %{
          name: name,
          slug: slug,
          definition: definition
        }
      }

    case http_client().request(base_request(), method: method, url: path, json: body) do
      {:ok, %Req.Response{status: status, body: %{"id" => ruleset_id}}} when status in [200, 201] ->
        {:ok, ruleset_id}

      {:ok, %Req.Response{status: 422, body: %{"slug" => ["has already been taken"]}}} ->
        {:error, "Slug already taken"}

      {:ok, %Req.Response{status: sc}} ->
        {:error, "Bad API response: Status code: #{sc}"}

      {:ok, _unsupported} ->
        {:error, "Unsupported response type"}

      {:error, e} ->
        {:error, Exception.message(e)}
    end
  end

  defp base_request do
    Req.new(base_url: @base_url, auth: auth())
  end

  defp auth do
    "Token token=#{Application.fetch_env!(:transport, :enroute_rulesets_token)}"
  end

  defp http_client, do: Transport.Req.impl()
end

defmodule Transport.EnRoute.ChouetteValidRulesetsClient.Slugs do
  @moduledoc """
  Helpers to manipulate rulesets slugs.
  """

  @type slug :: binary

  @spec check_slug!(slug :: binary()) :: slug()
  def check_slug!(slug) do
    if versioned_slug?(slug) do
      slug
    else
      raise "Invalid slug #{slug}"
    end
  end

  @spec versioned_slug?(slug :: binary()) :: boolean()
  @doc """
  iex> versioned_slug?("pan:profile:1")
  true
  iex> versioned_slug?("pan:profile")
  false
  """
  def versioned_slug?(slug) do
    case parse_slug(slug) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @spec sibling_slugs?(slug_a :: binary(), slug_b :: binary()) :: boolean()
  @doc """
  iex> sibling_slugs?("pan:profile:1", "pan:profile:2")
  true
  iex> sibling_slugs?("pan:profile", "pan:profile:2")
  false
  iex> sibling_slugs?("pan:profile:1", "pan:exceptions:2")
  false
  """
  def sibling_slugs?(slug_a, slug_b) do
    case {parse_slug(slug_a), parse_slug(slug_b)} do
      {{:ok, {basename_a, _}}, {:ok, {basename_b, _}}} -> basename_a == basename_b
      _ -> false
    end
  end

  defp parse_slug(slug) do
    case Regex.named_captures(~r/(?<basename>.*):(?<version>[0-9]+)$/, slug) do
      %{"basename" => basename, "version" => version} ->
        version = String.to_integer(version)
        {:ok, {basename, version}}

      _ ->
        :error
    end
  end
end
