defmodule GtfsValidatorTest do
  use ExUnit.Case, async: true
  doctest Shared.Validation.GtfsValidator

  import Mox

  alias Shared.Validation.GtfsValidator

  setup :verify_on_exit!

  test "test" do
    Mox.defmock(HTTPoison.BaseMock, for: HTTPoison.Base)
    Application.put_env(:transport, :gtfs_validator_http_client, HTTPoison.BaseMock)

    create_gtfs()
    |> GtfsValidator.validate()
    |> IO.inspect()
  end

  test "raise an error if gtfs_validator_url is not set" do
    Application.delete_env(:transport, :gtfs_validator_url)

    assert Application.fetch_env(:transport, :gtfs_validator_url) == :error

    assert_raise RuntimeError, fn ->
      create_gtfs()
      |> GtfsValidator.validate()
    end
  end

  test "Return validation report" do
    create_gtfs()
    |> GtfsValidator.validate()
    |> assert_validation_report_is_defined()
  end

  defp create_gtfs(), do: File.read!("#{__DIR__}/gtfs.zip")

  defp assert_validation_report_is_defined(validation_report), do:
    assert validation_report !== nil

end
