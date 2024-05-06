defmodule Transport.CompaniesTest do
  use ExUnit.Case, async: true
  alias Transport.Companies
  import Mox
  doctest Companies, import: true

  @siren "420495178"
  setup :verify_on_exit!

  describe "by_siren_or_siret" do
    test "validates formats" do
      assert {:error, :invalid_siren_siret_format} == Companies.by_siren_or_siret("420495179")
      assert {:error, :invalid_siren_siret_format} == Companies.by_siren_or_siret("42049517800016")
      assert {:error, :invalid_siren_siret_format} == Companies.by_siren_or_siret("foo")
    end

    test "result is found" do
      payload = %{
        "results" => [result = %{"siren" => @siren, "nom_complet" => "air france"}, %{"siren" => Ecto.UUID.generate()}]
      }

      response = {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(payload)}}
      setup_response_by_siren(@siren, response)

      assert {:ok, result} == Companies.by_siren_or_siret(@siren)
    end

    test "providing a valid SIRET searches for the associated SIREN" do
      siret = "42049517800014"
      assert String.starts_with?(siret, @siren)

      payload = %{
        "results" => [result = %{"siren" => @siren, "nom_complet" => "air france"}, %{"siren" => Ecto.UUID.generate()}]
      }

      response = {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(payload)}}
      setup_response_by_siren(@siren, response)

      assert {:ok, result} == Companies.by_siren_or_siret(siret)
    end

    test "500 from server" do
      response = {:ok, %HTTPoison.Response{status_code: 500}}
      setup_response_by_siren(@siren, response)

      assert {:error, :invalid_http_response} == Companies.by_siren_or_siret(@siren)
    end

    test "200 from server but siren is not found in the results" do
      payload = %{"results" => [%{"siren" => Ecto.UUID.generate(), "nom_complet" => "air france"}]}
      response = {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(payload)}}
      setup_response_by_siren(@siren, response)

      assert {:error, :result_not_found} == Companies.by_siren_or_siret(@siren)
    end

    test "timeout from server" do
      response = {:error, %HTTPoison.Error{reason: :timeout}}
      setup_response_by_siren(@siren, response)

      assert {:error, :http_error} == Companies.by_siren_or_siret(@siren)
    end
  end

  defp setup_response_by_siren(siren, response) do
    uri = %URI{
      scheme: "https",
      host: "recherche-entreprises.api.gouv.fr",
      port: 443,
      path: "/search",
      query: "mtm_campaign=transport-data-gouv-fr&q=#{siren}"
    }

    Transport.HTTPoison.Mock |> expect(:get, fn ^uri -> response end)
  end
end
