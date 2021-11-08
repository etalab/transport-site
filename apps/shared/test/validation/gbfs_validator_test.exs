defmodule GBFSValidatorTest do
  use ExUnit.Case, async: false
  doctest Shared.Validation.GBFSValidator

  import Mox

  alias Shared.Validation.GBFSValidator.Summary
  alias Shared.Validation.GBFSValidator.Wrapper, as: GBFSValidator

  setup do
    :verify_on_exit!
    # Do not use a mock for the GBFS Validator as we'll mock HTTP calls
    old_value = Application.fetch_env!(:transport, :gbfs_validator_impl)
    on_exit(fn -> Application.put_env(:transport, :gbfs_validator_impl, old_value) end)
    Application.put_env(:transport, :gbfs_validator_impl, Shared.Validation.GBFSValidator.HTTPClient)
  end

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
          {"summary":{"version":{"detected":"1.1","validated":"1.1"},"hasErrors":false,"errorsCount":0}}
         """,
         headers: [{"Content-Type", "application/json"}]
       }}
    end)

    expected = %Summary{
      errors_count: 0,
      has_errors: false,
      version_detected: "1.1",
      version_validated: "1.1"
    }
    assert {:ok, ^expected} = GBFSValidator.validate("https://example.com/gbfs.json")
  end

  test "on invalid server response" do
    Transport.HTTPoison.Mock |> expect(:post, fn _url, _, _ -> {:ok, %HTTPoison.Response
      {status_code: 500}} end)

    {:error, error} = GBFSValidator.validate("https://example.com/gbfs.json")
    assert String.starts_with?(error, "impossible to query GBFS Validator")
  end

  test "can encode summary" do
    assert """
    {"errors_count":0,"has_errors":false,"version_detected":"1.1","version_validated":"1.1"}\
    """
     == Jason.encode!(%Summary{
      errors_count: 0,
      has_errors: false,
      version_detected: "1.1",
      version_validated: "1.1"
    })
  end
end
