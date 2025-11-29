defmodule Transport.Validators.MobilityDataGTFSValidator do
  @moduledoc """
  Validate a GTFS using the Canonical GTFS Transport validator.
  """
  @behaviour Transport.Validators.Validator

  @impl Transport.Validators.Validator
  def validator_name, do: "MobilityData GTFS Validator"

  @impl Transport.Validators.Validator
  def validate_and_save(%DB.ResourceHistory{id: resource_history_id, payload: %{"permanent_url" => url}}) do
    job_id = validator_client().create_a_validation(url)
    result = job_id |> poll_validation_results()

    %DB.MultiValidation{
      validation_timestamp: DateTime.utc_now(),
      validator: validator_name(),
      validator_version: get_in(result, ["summary", "validatorVersion"]),
      result: result,
      digest: digest(Map.get(result, "notices", [])),
      command: command(job_id),
      resource_history_id: resource_history_id,
      max_error: get_max_severity_error(Map.get(result, "notices", []))
    }
    |> DB.Repo.insert!()

    :ok
  end

  def validate_and_save(gtfs_url) do
    validator_client().create_a_validation(gtfs_url) |> poll_validation_results()
  end

  def command(job_id) do
    validator_client().report_html_url(job_id)
  end

  defp poll_validation_results(job_id, attempt \\ 1)

  defp poll_validation_results(job_id, 60 = _attempt) do
    %{"status" => "error", "reason" => "timeout", "job_id" => job_id}
  end

  defp poll_validation_results(job_id, attempt) do
    case validator_client().get_a_validation(job_id) do
      :pending ->
        :timer.sleep(1_000)
        poll_validation_results(job_id, attempt + 1)

      {:successful, data} ->
        data

      {:error, data} ->
        data

      :unexpected_validation_status ->
        %{}
    end
  end

  @doc """
  iex> digest([%{"code" => "unusable_trip", "severity" => "WARNING", "totalNotices" => 2, "samplesNotices" => ["foo", "bar"]}])
  %{
    "max_severity" => %{"max_level" => "WARNING", "worst_occurrences" => 1},
    "stats" => %{"WARNING" => 1},
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

  @spec severity_level(binary()) :: non_neg_integer()
  def severity_level(key) do
    case key do
      "ERROR" -> 0
      "WARNING" -> 1
      "INFO" -> 2
      _ -> 3
    end
  end

  @doc """
  iex> count_by_severity([%{"severity" => "WARNING"}, %{"severity" => "WARNING"}])
  %{"WARNING" => 2}
  iex> count_by_severity([%{"severity" => "WARNING"}, %{"severity" => "ERROR"}])
  %{"WARNING" => 1, "ERROR" => 1}
  """
  @spec count_by_severity([map()]) :: map()
  def count_by_severity(validation_result) do
    validation_result |> Enum.map(& &1["severity"]) |> Enum.frequencies()
  end

  @doc """
  iex> count_max_severity([%{"severity" => "WARNING"}, %{"severity" => "WARNING"}])
  %{"max_level" => "WARNING", "worst_occurrences" => 2}
  iex> count_max_severity([%{"severity" => "ERROR"}, %{"severity" => "WARNING"}])
  %{"max_level" => "ERROR", "worst_occurrences" => 1}
  """
  @spec count_max_severity([map()]) :: map()
  def count_max_severity(validation_result) do
    {max_level, worst_occurrences} =
      validation_result
      |> count_by_severity()
      |> Enum.min_by(fn {severity, _count} -> severity |> severity_level() end)

    %{"max_level" => max_level, "worst_occurrences" => worst_occurrences}
  end

  @doc """
  iex> get_max_severity_error([%{"severity" => "WARNING"}, %{"severity" => "WARNING"}])
  "WARNING"
  iex> get_max_severity_error([%{"severity" => "ERROR"}, %{"severity" => "WARNING"}])
  "ERROR"
  iex> get_max_severity_error([%{"severity" => "ERROR"}, %{"severity" => "WARNING"}, %{"severity" => "INFO"}])
  "ERROR"
  """
  @spec get_max_severity_error([map()]) :: binary()
  def get_max_severity_error(validation_result) do
    %{"max_level" => max_level} = validation_result |> count_max_severity()
    max_level
  end

  defp validator_client, do: Transport.Validators.MobilityDataGTFSValidatorClient.Wrapper.impl()
end
