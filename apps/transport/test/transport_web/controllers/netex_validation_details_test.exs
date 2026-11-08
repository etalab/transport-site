defmodule TransportWeb.NeTExValidationDetailsTest do
  use ExUnit.Case, async: true

  import NeTExTestData
  alias Transport.Validators.NeTEx.ResultsAdapter
  alias TransportWeb.NeTExValidationDetails

  describe "build/3" do
    test "populates has_errors? as true when summary has entries" do
      version = "0.2.0"
      result = category_stats_result(version)
      errors = result |> Map.values() |> List.flatten()
      adapter = ResultsAdapter.resolve(version)
      df = adapter.to_dataframe(errors)

      multi_validation = %DB.MultiValidation{
        validator: Transport.Validators.NeTEx.Validator.validator_name(),
        validator_version: version,
        digest: adapter.digest(df),
        binary_result: adapter.to_binary_result(errors),
        metadata: %DB.ResourceMetadata{metadata: %{}, modes: []},
        validation_timestamp: ~U[2022-10-28 14:12:29.041243Z]
      }

      config = %Scrivener.Config{page_number: 1, page_size: 10}
      details = NeTExValidationDetails.build(multi_validation, config, %{})

      assert details.has_errors? == true
    end

    test "populates has_errors? as false when no errors (max_severity is NoError)" do
      version = "0.2.0"
      adapter = ResultsAdapter.resolve(version)
      df = adapter.to_dataframe([])

      multi_validation = %DB.MultiValidation{
        validator: Transport.Validators.NeTEx.Validator.validator_name(),
        validator_version: version,
        digest: adapter.digest(df),
        binary_result: adapter.to_binary_result([]),
        metadata: %DB.ResourceMetadata{metadata: %{}, modes: []},
        validation_timestamp: ~U[2022-10-28 14:12:29.041243Z]
      }

      config = %Scrivener.Config{page_number: 1, page_size: 10}
      details = NeTExValidationDetails.build(multi_validation, config, %{})

      assert details.has_errors? == false
      assert details.max_severity["max_level"] == "NoError"
    end

    test "populates retention_days from CleanOnDemandValidationJob" do
      version = "0.2.0"
      result = category_stats_result(version)
      errors = result |> Map.values() |> List.flatten()
      adapter = ResultsAdapter.resolve(version)
      df = adapter.to_dataframe(errors)

      multi_validation = %DB.MultiValidation{
        validator: Transport.Validators.NeTEx.Validator.validator_name(),
        validator_version: version,
        digest: adapter.digest(df),
        binary_result: adapter.to_binary_result(errors),
        metadata: %DB.ResourceMetadata{metadata: %{}, modes: []},
        validation_timestamp: ~U[2022-10-28 14:12:29.041243Z]
      }

      config = %Scrivener.Config{page_number: 1, page_size: 10}
      details = NeTExValidationDetails.build(multi_validation, config, %{})

      assert details.retention_days == Transport.Jobs.CleanOnDemandValidationJob.retention_days()
    end

    test "download_url defaults to nil" do
      version = "0.2.0"
      result = category_stats_result(version)
      errors = result |> Map.values() |> List.flatten()
      adapter = ResultsAdapter.resolve(version)
      df = adapter.to_dataframe(errors)

      multi_validation = %DB.MultiValidation{
        validator: Transport.Validators.NeTEx.Validator.validator_name(),
        validator_version: version,
        digest: adapter.digest(df),
        binary_result: adapter.to_binary_result(errors),
        metadata: %DB.ResourceMetadata{metadata: %{}, modes: []},
        validation_timestamp: ~U[2022-10-28 14:12:29.041243Z]
      }

      config = %Scrivener.Config{page_number: 1, page_size: 10}
      details = NeTExValidationDetails.build(multi_validation, config, %{})

      assert details.download_url == nil
    end

    test "returns empty struct when MultiValidation is nil" do
      config = %Scrivener.Config{page_number: 1, page_size: 10}
      details = NeTExValidationDetails.build(nil, config, %{})

      assert details == %NeTExValidationDetails{}
      refute details.has_errors?
      assert details.download_url == nil
    end

    test "returns empty struct when binary_result is nil" do
      multi_validation = %DB.MultiValidation{binary_result: nil}
      config = %Scrivener.Config{page_number: 1, page_size: 10}
      details = NeTExValidationDetails.build(multi_validation, config, %{})

      assert details == %NeTExValidationDetails{}
      refute details.has_errors?
    end
  end
end
