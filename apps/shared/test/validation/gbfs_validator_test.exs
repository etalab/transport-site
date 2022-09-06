defmodule GBFSValidatorTest do
  use ExUnit.Case, async: true
  doctest Shared.Validation.GBFSValidator

  import Mox
  import ExUnit.CaptureLog

  alias Shared.Validation.GBFSValidator.{HTTPValidatorClient, Summary}

  setup :verify_on_exit!

  test "validate GBFS feed" do
    Transport.HTTPoison.Mock
    |> expect(:post, fn url, body, headers ->
      assert %{"url" => "https://example.com/gbfs.json"} = Jason.decode!(body)
      assert [{"content-type", "application/json"}, {"user-agent", "contact@transport.beta.gouv.fr"}] == headers
      assert String.starts_with?(url, "https://gbfs-validator.netlify.app")

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: """
          {"summary":{"version":{"detected":"1.1","validated":"1.1"},"hasErrors":false,"errorsCount":0,"validatorVersion":"31c5325"}}
         """,
         headers: [{"Content-Type", "application/json"}]
       }}
    end)

    expected = %Summary{
      errors_count: 0,
      has_errors: false,
      version_detected: "1.1",
      version_validated: "1.1",
      validator_version: "31c5325",
      validator: Shared.Validation.GBFSValidator.HTTPValidatorClient
    }

    assert {:ok, ^expected} = HTTPValidatorClient.validate("https://example.com/gbfs.json")
  end

  test "on invalid server response" do
    Transport.HTTPoison.Mock
    |> expect(:post, fn _url, _, _ -> {:ok, %HTTPoison.Response{status_code: 500}} end)

    {{:error, error}, logs} = with_log(fn -> HTTPValidatorClient.validate("https://example.com/gbfs.json") end)

    assert String.starts_with?(error, "impossible to query GBFS Validator")
    assert logs =~ "impossible to query GBFS Validator"
  end

  test "can encode summary" do
    assert """
           {"errors_count":0,"has_errors":false,"validator":"validator_module","validator_version":"31c5325","version_detected":"1.1","version_validated":"1.1"}\
           """ ==
             Jason.encode!(%Summary{
               errors_count: 0,
               has_errors: false,
               version_detected: "1.1",
               version_validated: "1.1",
               validator_version: "31c5325",
               validator: :validator_module
             })
  end
end
