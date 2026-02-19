defmodule Transport.Validators.NeTEx.MetadataExtractor do
  @moduledoc """
  Analyses the content of a NeTEx archive and tries its best to extract some metadata including:
  - start_date and end_date (from calendar and service calendars)
  """

  alias Transport.NeTEx.ArchiveParser

  def extract(filepath) do
    Map.merge(extract_validity_dates(filepath), extract_networks(filepath))
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

  def extract_networks(filepath) do
    empty = %{"networks" => [], "modes" => []}

    try do
      run_parser(filepath, &ArchiveParser.read_all_description/1, empty, fn elem, acc ->
        %{
          "networks" => acc["networks"] ++ elem.networks,
          "modes" => uniq(acc["modes"] ++ elem.transport_modes)
        }
      end)
    rescue
      _ -> empty
    end
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

  defp uniq(list), do: list |> MapSet.new() |> MapSet.to_list()
end
