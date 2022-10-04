defmodule Transport.Validators.GTFSTransport do
  @moduledoc """
  Validate a GTFS with transport-validator (https://github.com/etalab/transport-validator/)
  """
  @behaviour Transport.Validators.Validator
  import TransportWeb.Gettext, only: [dgettext: 2]

  @no_error "NoError"
  @validator_name "GTFS transport-validator"

  @doc """
  Validates a resource history and extract metadata from it.
  Store the results in DB
  """
  @impl Transport.Validators.Validator
  def validate_and_save(%DB.ResourceHistory{
        id: resource_history_id,
        payload: %{"permanent_url" => url}
      }) do
    timestamp = DateTime.utc_now()
    validator = Shared.Validation.GtfsValidator.Wrapper.impl()

    with {:ok, %{"validations" => validations, "metadata" => metadata}} <-
           validator.validate_from_url(url),
         data_vis <- Transport.DataVisualization.validation_data_vis(validations) do
      resource_metadata = %DB.ResourceMetadata{
        resource_history_id: resource_history_id,
        metadata: metadata,
        modes: find_modes(metadata),
        features: find_tags(metadata)
      }

      %DB.MultiValidation{
        validation_timestamp: timestamp,
        validator: validator_name(),
        result: validations,
        data_vis: data_vis,
        command: command(url),
        resource_history_id: resource_history_id,
        metadata: resource_metadata,
        validator_version: Map.get(metadata, "validator_version"),
        max_error: get_max_severity_error(validations)
      }
      |> DB.Repo.insert!()

      :ok
    else
      e -> {:error, "#{validator_name()}, validation failed. #{inspect(e)}"}
    end
  end

  # https://github.com/etalab/transport-site/issues/2390
  # delete Shared.Validation.GtfsValidator.Wrapper and bring back the code here.
  def validate(url), do: Shared.Validation.GtfsValidator.Wrapper.impl().validate_from_url(url)

  @impl Transport.Validators.Validator
  def validator_name, do: @validator_name

  def command(url), do: Shared.Validation.GtfsValidator.remote_gtfs_validation_query(url)

  # Duplicates of function found in DB.Validation.
  # DB.Validation will be removed later
  @spec severities_map() :: map()
  def severities_map,
    do: %{
      "Fatal" => %{level: 0, text: dgettext("gtfs-transport-validator", "Fatal failures")},
      "Error" => %{level: 1, text: dgettext("gtfs-transport-validator", "Errors")},
      "Warning" => %{level: 2, text: dgettext("gtfs-transport-validator", "Warnings")},
      "Information" => %{level: 3, text: dgettext("gtfs-transport-validator", "Informations")}
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

  @spec summary(map) :: list
  def summary(%{} = validation_result) do
    validation_result
    |> Enum.map(fn {key, issues} ->
      {key,
       %{
         count: Enum.count(issues),
         title: issues_short_translation()[key],
         severity: issues |> List.first() |> Map.fetch!("severity")
       }}
    end)
    |> Map.new()
    |> Enum.group_by(fn {_, issue} -> issue.severity end)
    |> Enum.sort_by(fn {severity, _} -> severities(severity).level end)
  end

  @doc """
  Returns the number of issues by severity level

  iex> validation_result = %{"tooClose" => [%{"severity" => "Warning"}], "funnyName" => [%{"severity" => "Information"}, %{"severity" => "Information"}], "NullDuration" => [%{"severity" => "Warning"}]}
  iex> count_by_severity(validation_result)
  %{"Warning" => 2, "Information" => 2}

  iex> count_by_severity(%{})
  %{}
  """
  @spec count_by_severity(map()) :: map()
  def count_by_severity(%{} = validation_result) do
    validation_result
    |> Enum.flat_map(fn {_, v} -> v end)
    |> Enum.reduce(%{}, fn v, acc -> Map.update(acc, v["severity"], 1, &(&1 + 1)) end)
  end

  def count_by_severity(_), do: %{}

  @doc """
  Returns the maximum severity, with the issues count

  iex> validation_result = %{"tooClose" => [%{"severity" => "Warning"}], "funnyName" => [%{"severity" => "Information"}, %{"severity" => "Information"}], "NullDuration" => [%{"severity" => "Warning"}]}
  iex> count_max_severity(validation_result)
  {"Warning", 2}
  iex> count_max_severity(%{})
  {"NoError", 0}
  """
  @spec count_max_severity(map()) :: {binary(), integer()}
  def count_max_severity(validation_result) when validation_result == %{} do
    {@no_error, 0}
  end

  def count_max_severity(%{} = validation_result) do
    validation_result
    |> count_by_severity()
    |> Enum.min_by(fn {severity, _count} -> severity |> severities() |> Map.get(:level) end)
  end

  @spec is_mine?(any) :: boolean()
  def is_mine?(%{validator: validator}), do: validator == validator_name()
  def is_mine?(_), do: false

  @doc """
  Returns the maximum issue severity found

  iex> validation_result = %{"tooClose" => [%{"severity" => "Warning"}], "funnyName" => [%{"severity" => "Information"}, %{"severity" => "Information"}], "NullDuration" => [%{"severity" => "Warning"}]}
  iex> get_max_severity_error(validation_result)
  "Warning"

  iex> get_max_severity_error(%{})
  "NoError"

  iex> get_max_severity_error(nil)
  nil
  """
  @spec get_max_severity_error(any) :: binary() | nil
  def get_max_severity_error(%{} = validations) do
    {severity, _} = count_max_severity(validations)
    severity
  end

  def get_max_severity_error(_), do: nil

  @spec issues_short_translation() :: %{binary() => binary()}
  def issues_short_translation,
    do: %{
      "UnusedStop" => dgettext("gtfs-transport-validator", "Unused stops"),
      "Slow" => dgettext("gtfs-transport-validator", "Slow"),
      "ExcessiveSpeed" => dgettext("gtfs-transport-validator", "Excessive speed between two stops"),
      "NegativeTravelTime" => dgettext("gtfs-transport-validator", "Negative travel time between two stops"),
      "CloseStops" => dgettext("gtfs-transport-validator", "Close stops"),
      "NullDuration" => dgettext("gtfs-transport-validator", "Null duration between two stops"),
      "InvalidReference" => dgettext("gtfs-transport-validator", "Invalid reference"),
      "InvalidArchive" => dgettext("gtfs-transport-validator", "Invalid archive"),
      "MissingRouteName" => dgettext("gtfs-transport-validator", "Missing route name"),
      "MissingId" => dgettext("gtfs-transport-validator", "Missing id"),
      "MissingCoordinates" => dgettext("gtfs-transport-validator", "Missing coordinates"),
      "MissingName" => dgettext("gtfs-transport-validator", "Missing name"),
      "InvalidCoordinates" => dgettext("gtfs-transport-validator", "Invalid coordinates"),
      "InvalidRouteType" => dgettext("gtfs-transport-validator", "Invalid route type"),
      "MissingUrl" => dgettext("gtfs-transport-validator", "Missing url"),
      "InvalidUrl" => dgettext("gtfs-transport-validator", "Invalid url"),
      "InvalidTimezone" => dgettext("gtfs-transport-validator", "Invalid timezone"),
      "DuplicateStops" => dgettext("gtfs-transport-validator", "Duplicate stops"),
      "MissingPrice" => dgettext("gtfs-transport-validator", "Missing price"),
      "InvalidCurrency" => dgettext("gtfs-transport-validator", "Invalid currency"),
      "InvalidTransfers" => dgettext("gtfs-transport-validator", "Invalid transfers"),
      "InvalidTransferDuration" => dgettext("gtfs-transport-validator", "Invalid transfer duration"),
      "MissingLanguage" => dgettext("gtfs-transport-validator", "Missing language"),
      "InvalidLanguage" => dgettext("gtfs-transport-validator", "Invalid language"),
      "DuplicateObjectId" => dgettext("gtfs-transport-validator", "Duplicate object id"),
      "UnloadableModel" => dgettext("gtfs-transport-validator", "Not compliant with the GTFS specification"),
      "MissingMandatoryFile" => dgettext("gtfs-transport-validator", "Missing mandatory file"),
      "ExtraFile" => dgettext("gtfs-transport-validator", "Extra file"),
      "ImpossibleToInterpolateStopTimes" =>
        dgettext("gtfs-transport-validator", "Impossible to interpolate stop times"),
      "InvalidStopLocationTypeInTrip" => dgettext("gtfs-transport-validator", "Invalid stop location type in trip"),
      "InvalidStopParent" => dgettext("gtfs-transport-validator", "Invalid stop parent"),
      "IdNotAscii" => dgettext("gtfs-transport-validator", "ID is not ASCII-encoded")
    }

  @spec is_gtfs_outdated(any()) :: boolean | nil
  @doc """
  true if the gtfs is outdated
  false if not
  nil if we don't know

  iex> validation = %DB.MultiValidation{validator: validator_name(), metadata: %DB.ResourceMetadata{metadata: %{"end_date" => "1900-01-01"}}}
  iex> is_gtfs_outdated(validation)
  true
  iex> validation = %DB.MultiValidation{validator: validator_name(), metadata: %DB.ResourceMetadata{metadata: %{"end_date" => "2900-01-01"}}}
  iex> is_gtfs_outdated(validation)
  false
  iex> is_gtfs_outdated(%DB.MultiValidation{})
  nil
  iex> validation = %DB.MultiValidation{validator: validator_name(), metadata: %DB.ResourceMetadata{metadata: %{"end_date" => Date.utc_today() |> Date.to_iso8601()}}}
  iex> is_gtfs_outdated(validation)
  true
  """
  def is_gtfs_outdated(%DB.MultiValidation{validator: @validator_name} = multi_validation) do
    multi_validation
    |> DB.MultiValidation.get_metadata_info("end_date")
    |> case do
      nil ->
        nil

      end_date ->
        end_date |> Date.from_iso8601!() |> Date.compare(Date.utc_today()) !== :gt
    end
  end

  def is_gtfs_outdated(_), do: nil

  # all those functions come from resource.ex, but now live here as they are related to this validator
  @spec find_tags(map()) :: [binary()]
  def find_tags(metadata) do
    gtfs_base_tags()
    |> Enum.concat(find_tags_from_metadata(metadata))
    |> Enum.uniq()
  end

  def find_tags_from_metadata(metadata) do
    tags =
      metadata
      |> has_fares_tag()
      |> Enum.concat(has_shapes_tag(metadata))
      |> Enum.concat(has_odt_tag(metadata))
      |> Enum.concat(has_route_colors_tag(metadata))
      |> Enum.concat(has_pathways_tag(metadata))
      |> Enum.concat(has_bike_accessibility(metadata))
      |> Enum.concat(has_wheelchair_accessibility(metadata))

    Enum.each(tags, fn tag ->
      if tag not in existing_gtfs_tags() do
        raise "`#{tag}` is not a known tag"
      end
    end)

    tags
  end

  def existing_gtfs_tags,
    do: [
      "tarifs",
      "tracés de lignes",
      "transport à la demande",
      "couleurs des lignes",
      "description des correspondances",
      "informations sur l'accessibilité à vélo",
      "informations sur l'accessibilité en fauteuil roulant"
    ]

  @spec find_modes(map()) :: [binary()]
  def find_modes(%{"modes" => modes}), do: modes
  def find_modes(_), do: []

  # These tags are not translated because we'll need to be able to search for those tags
  @spec has_fares_tag(map()) :: [binary()]
  def has_fares_tag(%{"has_fares" => true}), do: ["tarifs"]
  def has_fares_tag(_), do: []

  @spec has_shapes_tag(map()) :: [binary()]
  def has_shapes_tag(%{"has_shapes" => true}), do: ["tracés de lignes"]
  def has_shapes_tag(_), do: []

  # check if the resource contains some On Demand Transport (odt) tags
  @spec has_odt_tag(map()) :: [binary()]
  def has_odt_tag(%{"some_stops_need_phone_agency" => true}), do: ["transport à la demande"]
  def has_odt_tag(%{"some_stops_need_phone_driver" => true}), do: ["transport à la demande"]
  def has_odt_tag(_), do: []

  @doc """
  Outputs a tag if at least 80% of GTFS routes have a custom color.

  iex> has_route_colors_tag(%{"lines_with_custom_color_count" => 8, "lines_count" => 10})
  ["couleurs des lignes"]
  iex> has_route_colors_tag(%{"lines_with_custom_color_count" => 7, "lines_count" => 10})
  []
  iex> has_route_colors_tag(%{"lines_with_custom_color_count" => 0, "lines_count" => 0})
  []
  """
  @spec has_route_colors_tag(map()) :: [binary()]
  def has_route_colors_tag(%{"lines_with_custom_color_count" => with_colors_count, "lines_count" => lines_count})
      when with_colors_count / lines_count * 100 >= 80,
      do: ["couleurs des lignes"]

  def has_route_colors_tag(_), do: []

  @spec has_pathways_tag(map()) :: [binary()]
  def has_pathways_tag(%{"has_pathways" => true}), do: ["description des correspondances"]
  def has_pathways_tag(_), do: []

  @spec has_bike_accessibility(map()) :: [binary()]
  def has_bike_accessibility(%{"trips_with_bike_info_count" => n}) when is_integer(n) and n > 0,
    do: ["informations sur l'accessibilité à vélo"]

  def has_bike_accessibility(_), do: []

  @spec has_wheelchair_accessibility(map()) :: [binary()]
  def has_wheelchair_accessibility(%{"trips_with_wheelchair_info_count" => n1, "stops_with_wheelchair_info_count" => n2})
      when is_integer(n1) and is_integer(n2) and (n1 > 0 or n2 > 0),
      do: ["informations sur l'accessibilité en fauteuil roulant"]

  def has_wheelchair_accessibility(_), do: []

  @spec gtfs_base_tags() :: [binary()]
  def gtfs_base_tags,
    do: ["position des stations", "horaires théoriques", "topologie du réseau"]
end
