defmodule Transport.Validators.GTFSTransport do
  @moduledoc """
  Validate a GTFS with transport-validator (https://github.com/etalab/transport-validator/)
  """
  @behaviour Transport.Validators.Validator
  import DB.Gettext, only: [dgettext: 2]

  @doc """
  Validates a resource history and extract metadata from it.
  Store the results in DB
  """
  @impl Transport.Validators.Validator
  def validate(%DB.ResourceHistory{id: resource_history_id, payload: %{"permanent_url" => url}}) do
    timestamp = DateTime.utc_now()
    validator = Shared.Validation.GtfsValidator.Wrapper.impl()

    with {:ok, %{"validations" => validations, "metadata" => metadata}} <-
           validator.validate_from_url(url),
         data_vis <- Transport.DataVisualization.validation_data_vis(validations) do
      metadata = %DB.ResourceMetadata{
        resource_history_id: resource_history_id,
        metadata: metadata
      }

      %DB.MultiValidation{
        validation_timestamp: timestamp,
        validator: validator_name(),
        result: validations,
        data_vis: data_vis,
        command: command(url),
        resource_history_id: resource_history_id,
        metadata: metadata
      }
      |> DB.Repo.insert!()

      :ok
    else
      e -> {:error, "#{validator_name()}, validation failed. #{inspect(e)}"}
    end
  end

  @impl Transport.Validators.Validator
  def validator_name, do: "GTFS transport-validator"

  defp command(url), do: Shared.Validation.GtfsValidator.remote_gtfs_validation_query(url)

  # Duplicates of function found in DB.Validation.
  # DB.Validation will be removed later
  @spec severities_map() :: map()
  def severities_map,
    do: %{
      "Fatal" => %{level: 0, text: dgettext("db-validations", "Fatal failures")},
      "Error" => %{level: 1, text: dgettext("db-validations", "Errors")},
      "Warning" => %{level: 2, text: dgettext("db-validations", "Warnings")},
      "Information" => %{level: 3, text: dgettext("db-validations", "Informations")},
      "Irrelevant" => %{level: 4, text: dgettext("db-validations", "Passed validations")}
    }

  @spec severities(binary()) :: %{level: integer(), text: binary()}
  def severities(key), do: severities_map()[key]

  @doc """
  Get issues from validation results. For a specific issue type if specified, or the most severe.

  iex> validation_result = %{"tooClose" => [%{"severity" => "Warning"}], "funnyName" => [%{"severity" => "Information"}]}
  iex> get_issues(validation_result, %{"issue_type" => "funnyName"})
  [%{"severity" => "Information"}]
  iex> get_issues(validation_result, %{"issue_type" => "BrokenFile"})
  []
  iex> get_issues(validation_result, nil)
  [%{"severity" => "Warning"}]
  iex> get_issues(%{}, nil)
  []
  iex> get_issues([], nil)
  []
  """
  def get_issues(%{} = validation_result, %{"issue_type" => issue_type}) do
    Map.get(validation_result, issue_type, [])
  end

  def get_issues(%{} = validation_result, _) do
    validation_result
    |> Map.values()
    |> Enum.sort_by(fn [%{"severity" => severity} | _] -> severities(severity).level end)
    |> List.first([])
  end

  def get_issues(_, _), do: []

  def summary(%{} = validation_result) do
    existing_issues =
      validation_result
      |> Enum.map(fn {key, issues} ->
        {key,
         %{
           count: Enum.count(issues),
           title: DB.Resource.issues_short_translation()[key],
           severity: issues |> List.first() |> Map.get("severity")
         }}
      end)
      |> Map.new()

    DB.Resource.issues_short_translation()
    |> Enum.map(fn {key, title} -> {key, %{count: 0, title: title, severity: "Irrelevant"}} end)
    |> Map.new()
    |> Map.merge(existing_issues)
    |> Enum.group_by(fn {_, issue} -> issue.severity end)
    |> Enum.sort_by(fn {severity, _} -> severities(severity).level end)
  end

  @doc """
  Returns the number of issues by severity level
  """
  def count_by_severity(%{} = validation_result) do
    validation_result
    |> Enum.flat_map(fn {_, v} -> v end)
    |> Enum.reduce(%{}, fn v, acc -> Map.update(acc, v["severity"], 1, &(&1 + 1)) end)
  end

  def count_by_severity(_), do: %{}

  def count_max_severity(%{} = validation_result) do
    validation_result
    |> count_by_severity()
    |> Enum.min_by(fn {severity, _count} -> severity |> severities() |> Map.get(:level) end)
  end

  @spec is_me?(any) :: boolean()
  def is_me?(%{validator: validator}), do: validator == validator_name()
  def is_me?(_), do: false
end
