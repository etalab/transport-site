defmodule Transport.Validators.MobilityDataGTFSValidator do
  @moduledoc """
  Validate a GTFS using the Canonical GTFS Transport validator.
  """
  @no_error "NoError"

  use Gettext, backend: TransportWeb.Gettext

  # The `rules.json` file comes from the release of the validator.
  # https://github.com/MobilityData/gtfs-validator/releases
  @rules :transport
         |> Application.app_dir("priv")
         |> Kernel.<>("/mobilitydata_gtfs_rules.json")
         |> File.read!()
         |> Jason.decode!()

  @behaviour Transport.Validators.Validator

  @impl Transport.Validators.Validator
  def validator_name, do: "MobilityData GTFS Validator"

  @impl Transport.Validators.Validator
  @spec validate_and_save(DB.ResourceHistory.t() | binary()) :: :ok | map()
  def validate_and_save(%DB.ResourceHistory{id: resource_history_id, payload: %{"permanent_url" => url}}) do
    results = run_validation(url)

    %DB.MultiValidation{
      validation_timestamp: DateTime.utc_now(),
      validator: validator_name(),
      validator_version: results.validator_version,
      result: results.result,
      digest: results.digest,
      command: results.command,
      resource_history_id: resource_history_id,
      max_error: results.max_error,
      metadata: %DB.ResourceMetadata{
        resource_history_id: resource_history_id,
        metadata: results.metadata,
        features: results.features
      }
    }
    |> DB.Repo.insert!()

    :ok
  end

  def validate_and_save(gtfs_url), do: run_validation(gtfs_url)

  defp run_validation(url) do
    job_id = validator_client().create_a_validation(url)
    result = job_id |> poll_validation_results()
    # the validator version may be missing
    # https://github.com/MobilityData/gtfs-validator/issues/2021
    validator_version = get_in(result, ["summary", "validatorVersion"]) || github_validator_version()

    metadata = %{
      "start_date" => get_in(result, ["summary", "feedInfo", "feedServiceWindowStart"]),
      "end_date" => get_in(result, ["summary", "feedInfo", "feedServiceWindowEnd"]),
      "counts" => get_in(result, ["summary", "counts"]),
      "agencies" => get_in(result, ["summary", "agencies"]),
      "feedInfo" => get_in(result, ["summary", "feedInfo"])
    }

    %{
      result: result,
      validator_version: validator_version,
      metadata: metadata,
      command: command(job_id),
      digest: digest(Map.get(result, "notices", [])),
      max_error: get_max_severity_error(Map.get(result, "notices", [])),
      features: get_in(result, ["summary", "gtfsFeatures"])
    }
  end

  def github_validator_version do
    Transport.Cache.fetch(
      "#{__MODULE__}::validator_version",
      fn ->
        %HTTPoison.Response{status_code: 200, body: body} =
          http_client().get!("https://api.github.com/repos/MobilityData/gtfs-validator/releases/latest")

        body |> Jason.decode!() |> Map.fetch!("tag_name") |> String.trim_leading("v")
      end,
      :timer.hours(1)
    )
  end

  def command(job_id) do
    validator_client().report_html_url(job_id)
  end

  defp poll_validation_results(job_id, attempt \\ 1)

  defp poll_validation_results(job_id, 60 = _attempt) do
    %{"status" => "error", "reason" => "timeout", "job_id" => job_id, "validation_performed" => false}
  end

  defp poll_validation_results(job_id, attempt) do
    case validator_client().get_a_validation(job_id) do
      :pending ->
        :timer.sleep(1_000)
        poll_validation_results(job_id, attempt + 1)

      {:successful, data} ->
        data

      {:error, data} ->
        Map.put(data, "validation_performed", false)

      :unexpected_validation_status ->
        %{"validation_performed" => false, "reason" => "unexpected_validation_status"}
    end
  end

  def mine?(%{validator: validator}), do: validator == validator_name()
  def mine?(_), do: false

  @doc """
  iex> digest([%{"code" => "unusable_trip", "severity" => "WARNING", "totalNotices" => 2, "samplesNotices" => ["foo", "bar"]}])
  %{
    "max_severity" => %{"max_level" => "WARNING", "worst_occurrences" => 2},
    "stats" => %{"WARNING" => 2},
    "summary" => [%{"code" => "unusable_trip", "severity" => "WARNING", "totalNotices" => 2}]
  }
  """
  @spec digest([map()]) :: map()
  def digest([]) do
    %{"stats" => nil, "max_severity" => nil, "summary" => nil}
  end

  def digest(validation_result) do
    %{
      "stats" => count_by_severity(validation_result),
      "max_severity" => count_max_severity(validation_result),
      "summary" => summary(validation_result)
    }
  end

  @doc """
  iex> summary([%{"code" => "unusable_trip", "severity" => "WARNING", "totalNotices" => 2, "samplesNotices" => ["foo", "bar"]}])
  [%{"code" => "unusable_trip", "severity" => "WARNING", "totalNotices" => 2}]
  """
  @spec summary([map()]) :: [map()]
  def summary(validation_result) do
    Enum.map(validation_result, &Map.take(&1, ["code", "severity", "totalNotices"]))
  end

  @doc """
  iex> Enum.map(["ERROR", "WARNING", "INFO"], &severity_level/1)
  [0, 1, 2]
  iex> assert_raise CaseClauseError, fn -> severity_level("NOPE") end
  """
  @spec severity_level(binary()) :: non_neg_integer()
  def severity_level(key) do
    case key do
      "ERROR" -> 0
      "WARNING" -> 1
      "INFO" -> 2
    end
  end

  @doc """
  iex> count_by_severity([%{"severity" => "WARNING", "totalNotices" => 2}, %{"severity" => "WARNING", "totalNotices" => 3}])
  %{"WARNING" => 5}
  iex> count_by_severity([%{"severity" => "WARNING", "totalNotices" => 2}, %{"severity" => "ERROR", "totalNotices" => 3}])
  %{"WARNING" => 2, "ERROR" => 3}
  """
  @spec count_by_severity([map()]) :: map()
  def count_by_severity(validation_result) do
    Enum.reduce(validation_result, %{}, fn notice, acc ->
      severity = notice["severity"]
      count = notice["totalNotices"]

      Map.update(acc, severity, count, fn existing_count ->
        existing_count + count
      end)
    end)
  end

  @doc """
  iex> count_max_severity([%{"severity" => "WARNING", "totalNotices" => 1}, %{"severity" => "WARNING", "totalNotices" => 2}])
  %{"max_level" => "WARNING", "worst_occurrences" => 3}
  iex> count_max_severity([%{"severity" => "ERROR", "totalNotices" => 1}, %{"severity" => "WARNING", "totalNotices" => 2}])
  %{"max_level" => "ERROR", "worst_occurrences" => 1}
  iex> count_max_severity([])
  %{"max_level" => "NoError", "worst_occurrences" => 0}
  """
  @spec count_max_severity([map()]) :: map()
  def count_max_severity(validation_result) when validation_result == [] do
    %{"max_level" => @no_error, "worst_occurrences" => 0}
  end

  def count_max_severity(validation_result) do
    {max_level, worst_occurrences} =
      validation_result
      |> count_by_severity()
      |> Enum.min_by(fn {severity, _count} -> severity |> severity_level() end)

    %{"max_level" => max_level, "worst_occurrences" => worst_occurrences}
  end

  @doc """
  iex> get_max_severity_error([%{"severity" => "WARNING", "totalNotices" => 1}, %{"severity" => "WARNING", "totalNotices" => 1}])
  "WARNING"
  iex> get_max_severity_error([%{"severity" => "ERROR", "totalNotices" => 1}, %{"severity" => "WARNING", "totalNotices" => 1}])
  "ERROR"
  iex> get_max_severity_error([%{"severity" => "ERROR", "totalNotices" => 1}, %{"severity" => "WARNING", "totalNotices" => 1}, %{"severity" => "INFO", "totalNotices" => 1}])
  "ERROR"
  iex> get_max_severity_error([])
  "NoError"
  """
  @spec get_max_severity_error([map()]) :: binary()
  def get_max_severity_error(validation_result) do
    %{"max_level" => max_level} = validation_result |> count_max_severity()
    max_level
  end

  @doc """
  iex> no_error?("ERROR")
  false
  iex> no_error?("NoError")
  true
  """
  def no_error?(%{severity: severity}), do: no_error?(severity)
  def no_error?(severity), do: severity == @no_error

  @doc """
  iex> Gettext.put_locale("en")
  iex> format_severity("ERROR", 1)
  "1 error"
  iex> format_severity("ERROR", 2)
  "2 errors"
  iex> Gettext.put_locale("fr")
  iex> format_severity("ERROR", 1)
  "1 erreur"
  iex> format_severity("ERROR", 2_000)
  "2 000 erreurs"
  iex> assert_raise CaseClauseError, fn -> format_severity("NOPE", 42) end
  """
  @spec format_severity(binary(), non_neg_integer()) :: binary()
  def format_severity(key, count) do
    case key do
      "ERROR" ->
        dngettext("gtfs-transport-validator", "Error", "Errors", count, value: Helpers.format_number(count))

      "WARNING" ->
        dngettext("gtfs-transport-validator", "Warning", "Warnings", count, value: Helpers.format_number(count))

      "INFO" ->
        dngettext("gtfs-transport-validator", "Information", "Informations", count, value: Helpers.format_number(count))
    end
  end

  @doc """
  iex> rule_for_code("attribution_without_role") |> Map.keys()
  ["code", "deprecated", "description", "properties", "references", "severityLevel", "shortSummary", "type"]
  """
  @spec rule_for_code(binary()) :: map()
  def rule_for_code(code), do: Map.fetch!(@rules, code)

  defp validator_client, do: Transport.Validators.MobilityDataGTFSValidatorClient.Wrapper.impl()

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
