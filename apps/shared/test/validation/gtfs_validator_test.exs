defmodule GtfsValidatorTest do
  use ExUnit.Case, async: true
  doctest Shared.Validation.GtfsValidator

  import Mox

  alias Shared.Validation.GtfsValidator

  setup :verify_on_exit!

  test "validate gtfs zip file" do
    expected_validation_report = %{"text" => "GTFS is great"}

    create_gtfs()
    |> tap(&expect_validator_called_with_gtfs_and_return_report(&1, expected_validation_report))
    |> GtfsValidator.validate()
    |> assert_validation_report_is(expected_validation_report)
  end

  test "validate gtfs url" do
    gtfs_url = "http://my-domain.com/gtfs.zip"
    expected_validation_report = %{"text" => "GTFS is great"}

    expect_validator_called_with_gtfs_url_and_return_report(gtfs_url, expected_validation_report)

    gtfs_url
    |> GtfsValidator.validate_from_url()
    |> assert_validation_report_is(expected_validation_report)
  end

  defp assert_validation_report_is({:ok, obtained_validation_report}, expected_validation_report),
    do: assert(obtained_validation_report == expected_validation_report)

  defp create_gtfs, do: File.read!("#{__DIR__}/gtfs.zip")

  defp expect_validator_called_with_gtfs_and_return_report(_gtfs, expected_validation_report),
    do:
      Transport.HTTPoison.Mock
      |> expect(
        :post,
        fn "https://validation.transport.data.gouv.fr/validate", _gtfs, _, _ ->
          {:ok, %{status_code: 200, body: Jason.encode!(expected_validation_report)}}
        end
      )

  defp expect_validator_called_with_gtfs_url_and_return_report(gtfs_url, expected_validation_report),
    do:
      Transport.HTTPoison.Mock
      |> expect(
        :get,
        fn obtained_validator_url, _, _ ->
          # Le validateur doit être appelé en passant le lien de téléchargement du fichier GTFS
          expected_validator_url =
            "https://validation.transport.data.gouv.fr/validate?url=#{URI.encode_www_form(gtfs_url)}"

          assert obtained_validator_url == expected_validator_url

          {:ok, %{status_code: 200, body: Jason.encode!(expected_validation_report)}}
        end
      )
end
