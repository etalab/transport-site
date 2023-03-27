defmodule Transport.Companies do
  @moduledoc """
  An HTTP client for the "Recherche d'entreprises API"
  See the documentation: https://api.gouv.fr/documentation/api-recherche-entreprises
  ⚠️ rate limit is 7 requests per second, watch out if you're using this in a batch job.
  See a sample response:
  https://recherche-entreprises.api.gouv.fr/search?q=420495178
  """
  @endpoint URI.new!("https://recherche-entreprises.api.gouv.fr/search")

  @doc """
  Find a company registered in France using its SIREN or one of its SIRET number.
  If you provide a SIRET number, it will search using its SIREN number
  and **will not** check that the establishment is currently active.
  """
  @spec by_siren_or_siret(binary()) :: {:ok, map()} | {:error, atom()}
  def by_siren_or_siret(siren_or_siret) do
    cond do
      is_valid_siren?(siren_or_siret) -> by_siren(siren_or_siret)
      is_valid_siret?(siren_or_siret) -> siren_or_siret |> siret_to_siren() |> by_siren()
      true -> {:error, :invalid_siren_siret_format}
    end
  end

  @doc """
  Find a company registered in France using its SIREN number.
  """
  @spec by_siren(binary()) :: {:ok, map()} | {:error, atom()}
  def by_siren(siren) do
    find_siren = fn result -> if result["siren"] == siren, do: {:ok, result} end

    if is_valid_siren?(siren) do
      case search(%{"q" => siren}) do
        {:ok, json} ->
          json
          |> Map.get("results", [])
          |> Enum.find_value({:error, :result_not_found}, find_siren)

        {:error, _} = error_details ->
          error_details
      end
    else
      {:error, :invalid_siren_format}
    end
  end

  @doc """
  Call the "Recherche d'entreprises API" with the specified params.
  See the documentation for available params: https://api.gouv.fr/documentation/api-recherche-entreprises
  """
  @spec search(map()) :: {:ok, map()} | {:error, atom()}
  def search(%{} = params) do
    case params |> build_url() |> http_client().get() do
      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body |> Jason.decode!()}

      {:ok, %HTTPoison.Response{}} ->
        {:error, :invalid_http_response}

      {:error, %HTTPoison.Error{}} ->
        {:error, :http_error}
    end
  end

  @doc """
  iex> build_url(%{"q" => "420495178"})
  %URI{
    host: "recherche-entreprises.api.gouv.fr",
    path: "/search",
    port: 443,
    query: "q=420495178",
    scheme: "https"
  }
  """
  def build_url(%{} = uri_params) do
    @endpoint |> URI.append_query(URI.encode_query(uri_params))
  end

  @doc """
  Check if a SIREN appears to be valid: expected length and valid Luhn checksum.

  iex> is_valid_siren?("420495178")
  true
  iex> is_valid_siren?("420495179")
  false
  iex> is_valid_siren?("foo")
  false
  iex> is_valid_siren?("42049517800014")
  false
  """
  def is_valid_siren?(siren) when is_binary(siren) do
    String.match?(siren, ~r/^\d{9}$/) and Luhn.valid?(siren)
  end

  @doc """
  Check if a SIRET appears to be valid: expected length and valid Luhn checksum.

  iex> is_valid_siret?("420495178")
  false
  iex> is_valid_siret?("foo")
  false
  iex> is_valid_siret?("42049517800014")
  true
  iex> is_valid_siret?("42049517800015")
  false
  """
  def is_valid_siret?(siret) when is_binary(siret) do
    String.match?(siret, ~r/^\d{14}$/) and Luhn.valid?(siret)
  end

  @doc """
  iex> siret_to_siren("42049517800015")
  "420495178"
  """
  def siret_to_siren(siret), do: String.slice(siret, 0..8)

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
