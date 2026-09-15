defmodule Transport.Validators.NeTEx.MetadataExtractor do
  @moduledoc """
  Analyses the content of a NeTEx archive and tries its best to extract some metadata including:
  - start_date and end_date (from calendar and service calendars)
  """

  alias Transport.NeTEx.ArchiveParser

  def extract(filepath) do
    Map.merge(
      extract_validity_dates(filepath),
      Map.merge(describe_content(filepath), extract_publication_info(filepath))
    )
  end

  def extract_validity_dates(filepath) do
    case validity_dates(filepath) do
      {start_date, end_date} ->
        %{
          "start_date" => start_date |> Date.to_iso8601(),
          "end_date" => end_date |> Date.to_iso8601()
        }

      _ ->
        no_validity_dates()
    end
  rescue
    _ -> no_validity_dates()
  end

  def describe_content(filepath) do
    empty = %{
      "networks" => [],
      "modes" => [],
      "stats" => %{
        "lines_count" => 0,
        "quays_count" => 0,
        "stop_places_count" => 0
      },
      "features" => %{
        "networks" => false,
        "stops" => false,
        "timetables" => false,
        "fares" => false,
        "parkings" => false,
        "accessibility" => false
      }
    }

    try do
      run_parser(filepath, &ArchiveParser.read_all_description/1, empty, fn elem, acc ->
        %{
          "networks" => acc["networks"] ++ elem.networks,
          "modes" => uniq(acc["modes"] ++ elem.transport_modes),
          "stats" => %{
            "lines_count" => acc["stats"]["lines_count"] + elem.lines,
            "quays_count" => acc["stats"]["quays_count"] + elem.quays,
            "stop_places_count" => acc["stats"]["stop_places_count"] + elem.stop_places
          },
          "features" => %{
            "networks" => acc["features"]["networks"] || elem.features.networks,
            "stops" => acc["features"]["stops"] || elem.features.stops,
            "timetables" => acc["features"]["timetables"] || elem.features.timetables,
            "fares" => acc["features"]["fares"] || elem.features.fares,
            "parkings" => acc["features"]["parkings"] || elem.features.parkings,
            "accessibility" => acc["features"]["accessibility"] || elem.features.accessibility
          }
        }
      end)
    rescue
      _ -> empty
    end
  end

  @doc """
  Extract the earliest publication timestamp from all XML files in the archive.

  Returns `%{"publication_date" => iso8601_string}` if any `PublicationTimestamp`
  was found, or `%{}` otherwise. Fallbacks to upload date / today are handled
  by `NeTEx.Validator.determine_xsd_version/2`.
  """
  def extract_publication_info(filepath) do
    case earliest_publication_timestamp(filepath) do
      %Date{} = date ->
        %{"publication_date" => Date.to_iso8601(date)}

      nil ->
        %{}
    end
  rescue
    _ -> %{}
  end

  defp no_validity_dates, do: %{"no_validity_dates" => true}

  defp validity_dates(filepath) do
    all_dates =
      validity_dates_from_service_calendars(filepath) ++
        validity_dates_from_calendars(filepath)

    dates_range(all_dates, :start_date, :end_date)
  end

  defp validity_dates_from_calendars(filepath) do
    run_parser(filepath, &ArchiveParser.read_all_calendars/1)
  end

  defp validity_dates_from_service_calendars(filepath) do
    run_parser(filepath, &ArchiveParser.read_all_service_calendars/1)
  end

  defp run_parser(filepath, parser, empty \\ [], msum \\ &Kernel.++/2) do
    filepath
    |> parser.()
    |> flatten(empty, msum)
  end

  defp dates_range([], _, _), do: nil

  defp dates_range(values, start_key, end_key) do
    {
      Enum.min_by(values, & &1[start_key], Date)[start_key],
      Enum.max_by(values, & &1[end_key], Date)[end_key]
    }
  end

  defp flatten(per_files, empty, msum) do
    Enum.reduce(per_files, empty, fn {_filename, found}, acc ->
      case found do
        {:ok, values} -> msum.(values, acc)
        _ -> acc
      end
    end)
  end

  defp earliest_publication_timestamp(filepath) do
    timestamps =
      filepath
      |> ArchiveParser.read_all_publication_timestamps()
      |> Enum.flat_map(fn {_filename, result} ->
        case result do
          {:ok, %Date{} = date} -> [date]
          _ -> []
        end
      end)

    if timestamps == [], do: nil, else: Enum.min(timestamps)
  end

  defp uniq(list), do: list |> MapSet.new() |> MapSet.to_list()
end
