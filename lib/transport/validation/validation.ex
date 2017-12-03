defmodule Transport.Validation do
  @moduledoc """
    Represent a validation produced by transitfeed validation
  """

  import TransportWeb.Gettext
  import Logger
  alias Transport.ReusableData

  @epoch :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})

  def to_str(%{"type" => "<class 'transitfeed.problems.MissingValue'>",
               "dict" => dict}) do
    dgettext("validations", "Missing value for column %{column_name}",
      column_name: dict["column_name"])
  end

  def to_str(%{"type" => "<class 'transitfeed.problems.StopsTooClose'>",
               "dict" => dict}) do
    dgettext("validations",
      """
      The stops "%{stop_name_a}" (ID %{stop_id_a}) and "%{stop_name_b}" (ID %{stop_id_b}) are %{distance}m apart and probably represent  the same location.
      """,
      stop_name_a: dict["stop_name_a"], stop_id_a: dict["stop_id_a"],
      stop_name_b: dict["stop_name_b"], stop_id_b: dict["stop_id_b"],
      distance: dict["distance"])
  end

  def to_str(%{
      "type" =>
        "<class 'transitfeed.problems.TooManyConsecutiveStopTimesWithSameTime'>",
      "dict" => dict}) do
    dgettext("validations",
      """
      Trip %{trip_id} has %{number_of_stop_times} consecutive stop times all with the same arrival/departure time: %{stop_time}.
      """,
      trip_id: dict["trip_id"],
      number_of_stop_times: dict["number_of_stop_times"],
      stop_time: dict["stop_time"])
  end

  def to_str(%{"type" => "<class 'transitfeed.problems.TooFastTravel'>",
               "dict" => dict}) do
    if dict["speed"] == nil do
      dgettext("validations",
        """
        High speed travel detected in trip %{trip_id}: %{prev_stop} to %{next_stop}. %{dist} meters in %{time} seconds.
        """, trip_id: dict["trip_id"], prev_stop: dict["prev_stop"],
        next_stop: dict["next_stop"], time: dict["time"], dist: dict["dist"])
    else
      dgettext("validations",
        """
        High speed travel detected in trip %{trip_id}: %{prev_stop}" to %{next_stop}. %{dist} meters in %{time} seconds. (%{speed} km/h).
        """, trip_id: dict["trip_id"], prev_stop: dict["prev_stop"],
        next_stop: dict["next_stop"], time: dict["time"], speed: dict["speed"],
        dist: dict["dist"])
    end
  end

  def to_str(%{"type" => "<class 'transitfeed.problems.InvalidFloatValue'>",
               "dict" => dict}) do
    dgettext("validations",
      """
      Invalid numeric value %{value}. 
      Please ensure that the number includes an explicit whole number portion (ie. use 0.5 instead of .5), that you do not use the exponential notation (ie. use 0.001 instead of 1E-3), and that it is a properly formated decimal value.")
      """, value: dict["value"])
  end

  def to_str(%{"type" => "<class 'transitfeed.problems.InvalidValue'>",
               "dict" => dict}) do
    dgettext("validations", "Invalid value %{value} in field %{column_name}",
      value: dict["value"], column_name: dict["column_name"])
  end

  def to_str(%{"type" => "<class 'transitfeed.problems.UnrecognizedColumn'>",
               "dict" => dict}) do
    dgettext("validations",
      """
      Unrecognized column %{column_name} in file %{file_name}.
      This might be a misspelled column name (capitalization matters!). Or it could be extra information (such as a proposed feed extension) that the validator doesn't know about yet. Extra information is fine; this warning is here to catch misspelled optional column names.
      """, column_name: dict["column_name"], file_name: dict["file_name"])
  end

  def to_str(%{"type" => "<class 'transitfeed.problems.ExpirationDate'>",
               "dict" => dict}) do
    epoch_expiration = (@epoch) + round(dict["expiration"])
    {{year, month, day}, _} = :calendar.gregorian_seconds_to_datetime(epoch_expiration)
    dgettext("validations", "This feed expires on %{year}/%{month}/%{day}",
      year: year, month: month, day: day)
  end

  def to_str(%{"type" => "<class 'transitfeed.problems.StopTooFarFromParentStation'>",
               "dict" => dict}) do
    dgettext("validations",
      """
      %{stop_name} (ID %{stop_id}) is too far from its parent station %{parent_stop_name} (ID %{parent_stop_id}) : %{distance} meters.
      """, stop_name: dict["stop_name"], stop_id: dict["stop_id"],
      parent_stop_name: dict["parent_stop_name"],
      parent_stop_id: dict["parent_stop_id"],
      distance: dict["distance"])
  end

  def to_str(%{"type" => "<class 'transitfeed.problems.DifferentStationTooClose'>",
               "dict" => dict}) do
    dgettext("validations",
      """
      The parent_station of stop "%{stop_name}" (ID %{stop_id}) is not station "%{station_stop_name}" (ID %{station_stop_id}) but they are " only %{distance} apart.")
      """, stop_name: dict["stop_name"], stop_id: dict["stop_id"],
      station_stop_name: dict["station_stop_name"],
      station_stop_id: dict["station_stop_id"],
      distance: dict["distance"])
  end

  def to_str(%{"type" => "<class 'transitfeed.problems.UnknownFile'>",
               "dict" => dict}) do
    dgettext("validations",
      """
      The file named %{file_name} was not expected.
      This may be a misspelled file name or the file may be included in a subdirectory. Please check spellings and make sure that there are no subdirectories within the feed
      """, file_name: dict["file_name"])
  end

  def to_str(%{"type" => "<class 'transitfeed.problems.UnusedStop'>",
               "dict" => dict}) do
    dgettext("validations",
      "%{stop_name} (ID %{stop_id}) isn't used in any trips",
      stop_name: dict["stop_name"], stop_id: dict["stop_id"])
  end

  def to_str(%{"type" => "<class 'transitfeed.problems.OtherProblem'>",
               "dict" => dict}) do
    dgettext("validations", "%{description}", description: dict["description"])
  end

  def to_str(validation) do
    Logger.error("Unknown validation error #{validation.type}")
    nil
  end

  @doc """
    List errors
  """
  @spec list_errors(String.t) :: Map.t
  def list_errors(slug) do
    validations = slug
                  |> ReusableData.get_dataset
                  |> Map.get(:validations)
    %{"errors" => Enum.map(validations["errors"], &to_str/1)
                  |> Enum.filter(&(&1 != nil)),
      "warnings" => Enum.map(validations["warnings"], &to_str/1)
                    |> Enum.filter(&(&1 != nil)),
      "notices" => Enum.map(validations["notices"], &to_str/1)
                   |> Enum.filter(&(&1 != nil))
    }
  end
end
