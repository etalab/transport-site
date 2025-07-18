defmodule Transport.GTFSDiff do
  @moduledoc """
  Compute Diff between two GTFS files
  """
  alias NimbleCSV.RFC4180, as: CSV
  require Logger
  use Gettext, backend: TransportWeb.Gettext

  @primary_keys %{
    "agency.txt" => ["agency_id"],
    "stops.txt" => ["stop_id"],
    "routes.txt" => ["route_id"],
    "trips.txt" => ["trip_id"],
    "stop_times.txt" => ["trip_id", "stop_id", "stop_sequence"],
    "calendar.txt" => ["service_id"],
    "calendar_dates.txt" => ["service_id", "date"],
    "shapes.txt" => ["shape_id", "shape_pt_sequence"],
    "frequencies.txt" => ["trip_id", "start_time", "end_time"],
    "transfers.txt" => ["from_stop_id", "to_stop_id"],
    "pathways.txt" => ["pathway_id"],
    "levels.txt" => ["level_id"],
    "feed_info.txt" => ["feed_publisher_name"],
    "translations.txt" => ["table_name", "field_name", "language", "record_id", "record_sub_id", "field_value"],
    "attributions.txt" => ["organization_name"],
    "fare_attributes.txt" => ["fare_id"],
    "fare_products.txt" => ["fare_product_id"],
    "booking_rules.txt" => ["booking_rule_id"]
  }

  def unzip(file_path) do
    zip_file = Unzip.LocalFile.open(file_path)
    {:ok, unzip} = Unzip.new(zip_file)
    unzip
  end

  def unzip_contains_file?(unzip, file_name) do
    unzip
    |> Unzip.list_entries()
    |> Enum.any?(&(&1.file_name == file_name))
  end

  def parse_from_unzip(unzip, file_name) do
    if unzip_contains_file?(unzip, file_name) do
      unzip
      |> Unzip.file_stream!(file_name)
      |> Stream.map(fn c -> IO.iodata_to_binary(c) end)
      |> CSV.to_line_stream()
      |> CSV.parse_stream(skip_headers: false)
      |> parse_to_map(file_name)
    else
      %{}
    end
  end

  def parse_from_path(file_path, file_name) do
    file_path
    |> File.read!()
    |> parse_from_binary(file_name)
  end

  def parse_from_binary(binary, file_name) do
    binary
    |> CSV.parse_string(skip_headers: false)
    |> parse_to_map(file_name)
  end

  def parse_to_map(parsed_csv, file_name) do
    primary_key = primary_key(file_name)

    {res, _headers} =
      parsed_csv
      |> Enum.reduce({}, fn r, acc ->
        if acc == {} do
          {%{}, r |> Enum.map(fn h -> h |> String.replace_prefix("\uFEFF", "") end)}
        else
          {m, headers} = acc
          new_row = headers |> Enum.zip(r) |> Enum.into(%{})
          key = new_row |> row_key(primary_key)
          {m |> Map.put(key, new_row), headers}
        end
      end)

    res
  end

  def parse_diff_output(binary) do
    {l, _headers} =
      binary
      |> CSV.parse_string(skip_headers: false)
      |> Enum.reduce([], fn r, acc ->
        if acc == [] do
          {[], r |> Enum.map(fn h -> h |> String.replace_prefix("\uFEFF", "") end)}
        else
          {l, headers} = acc
          new_row = headers |> Enum.zip(r) |> Enum.into(%{})
          {[new_row | l], headers}
        end
      end)

    l |> Enum.reverse()
  end

  def get_headers(unzip, file_name) do
    if unzip_contains_file?(unzip, file_name) do
      unzip
      |> Unzip.file_stream!(file_name)
      |> Stream.map(fn c -> IO.iodata_to_binary(c) end)
      |> CSV.to_line_stream()
      |> CSV.parse_stream(skip_headers: false)
      # cannot take only the headers, I crash
      |> Enum.reduce({}, &save_headers_in_acc(&1, &2))
    else
      []
    end
  end

  defp save_headers_in_acc(r, {}) do
    r |> Enum.map(fn h -> h |> String.replace_prefix("\uFEFF", "") end)
  end

  defp save_headers_in_acc(_r, acc), do: acc

  def get_headers(file_path) do
    file_path
    |> File.read!()
    |> CSV.parse_string(skip_headers: false)
    |> Enum.at(0)
  end

  def file_is_handled?(file_name), do: not (file_name |> primary_key() |> is_nil())

  def primary_key(file_name) do
    Map.get(@primary_keys, file_name)
  end

  def row_key(row, nil) do
    # without a primary_key, the primary_key is the entire row
    row
  end

  def row_key(row, primary_key) do
    row |> Map.take(primary_key)
  end

  def get_delete_messages(deleted_ids, file_name) do
    deleted_ids
    |> Enum.map(fn identifier ->
      %{file: file_name, action: "delete", target: "row", identifier: identifier}
    end)
  end

  def get_add_messages(added_ids, file_b, file_name) do
    added_ids
    |> Enum.map(fn identifier ->
      added = file_b |> Map.fetch!(identifier)
      %{file: file_name, action: "add", target: "row", identifier: identifier, new_value: added}
    end)
  end

  def get_update_messages(update_ids, file_a, file_b, file_name) do
    check_value = fn a_value, key, b_value ->
      case a_value do
        ^b_value -> nil
        _new_value -> %{initial_value: {key, a_value}, new_value: {key, b_value}}
      end
    end

    update_ids
    |> Enum.map(fn identifier ->
      row_a = file_a |> Map.fetch!(identifier)
      row_b = file_b |> Map.fetch!(identifier)

      b_keys = row_b |> Map.keys()

      arg =
        b_keys
        |> Enum.map(fn key ->
          b_value = row_b |> Map.fetch!(key)

          row_a |> Map.get(key, "") |> check_value.(key, b_value)
        end)
        |> Enum.reject(&is_nil/1)

      if arg !== [] do
        %{
          file: file_name,
          action: "update",
          target: "row",
          identifier: identifier,
          initial_value: arg |> Enum.map(fn m -> m.initial_value end) |> Enum.into(%{}),
          new_value: arg |> Enum.map(fn m -> m.new_value end) |> Enum.into(%{})
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  def diff_file(file_name, file_a, file_b) do
    ids_a = file_a |> Map.keys()
    ids_b = file_b |> Map.keys()

    deleted_ids = ids_a -- ids_b
    added_ids = ids_b -- ids_a

    update_messages =
      if file_name |> file_is_handled?() do
        update_ids = ids_a -- deleted_ids
        update_ids |> get_update_messages(file_a, file_b, file_name)
      else
        # if file is not handled, only add and delete can be detected.
        []
      end

    delete_messages = deleted_ids |> get_delete_messages(file_name)
    add_messages = added_ids |> get_add_messages(file_b, file_name)

    delete_messages ++ add_messages ++ update_messages
  end

  def compare_files(unzip_1, unzip_2, profile \\ "full") do
    file_names_1 = unzip_1 |> list_entries(profile)
    file_names_2 = unzip_2 |> list_entries(profile)
    added_files = file_names_2 -- file_names_1
    deleted_files = file_names_1 -- file_names_2

    %{
      added_files: added_files,
      deleted_files: deleted_files,
      same_files: file_names_2 -- added_files
    }
  end

  def file_diff(unzip_1, unzip_2) do
    %{added_files: added_files, deleted_files: deleted_files} = compare_files(unzip_1, unzip_2)

    added_files_diff =
      added_files
      |> Enum.map(fn file ->
        %{file: file, action: "add", target: "file", identifier: %{filename: file}}
      end)

    deleted_files_diff =
      deleted_files
      |> Enum.map(fn file ->
        %{file: file, action: "delete", target: "file", identifier: %{filename: file}}
      end)

    added_files_diff ++ deleted_files_diff
  end

  def column_diff(unzip_1, unzip_2) do
    %{same_files: same_files, added_files: added_files} = compare_files(unzip_1, unzip_2)

    (same_files ++ added_files)
    |> Enum.flat_map(fn file_name ->
      column_name_1 = get_headers(unzip_1, file_name)

      column_name_2 = get_headers(unzip_2, file_name)

      added_column_diff =
        (column_name_2 -- column_name_1)
        |> Enum.map(fn column_name ->
          %{
            file: file_name,
            action: "add",
            target: "column",
            identifier: %{column: column_name}
          }
        end)

      deleted_column_diff =
        (column_name_1 -- column_name_2)
        |> Enum.map(fn column_name ->
          %{
            file: file_name,
            action: "delete",
            target: "column",
            identifier: %{column: column_name}
          }
        end)

      res = added_column_diff ++ deleted_column_diff
      res
    end)
    |> Enum.reject(&(&1 == []))
  end

  def row_diff(unzip_1, unzip_2, notify_func, locale, profile) do
    file_names_2 = unzip_2 |> list_entries(profile)

    file_names_2
    |> Enum.flat_map(fn file_name ->
      Logger.info("Computing diff for #{file_name}")

      unless is_nil(notify_func) do
        file_name |> computing_diff_log_message(locale) |> notify_func.()
      end

      file_1 = parse_from_unzip(unzip_1, file_name)
      file_2 = parse_from_unzip(unzip_2, file_name)
      diff_file(file_name, file_1, file_2)
    end)
  end

  defp computing_diff_log_message(file_name, locale) do
    Gettext.with_locale(locale, fn ->
      dgettext("gtfs-diff", "Computing diff for <code>%{file_name}</code>", file_name: file_name)
    end)
  end

  def diff(unzip_1, unzip_2, profile, notify_func \\ nil, locale \\ "fr") do
    file_diff = file_diff(unzip_1, unzip_2)
    column_diff = column_diff(unzip_1, unzip_2)
    row_diff = row_diff(unzip_1, unzip_2, notify_func, locale, profile)

    diff = file_diff ++ column_diff ++ row_diff
    id_range = 0..(Enum.count(diff) - 1)//1

    diff |> Enum.zip_with(id_range, &Map.merge(&1, %{id: &2}))
  end

  def dump_diff(diff, filepath) do
    headers = ["id", "file", "action", "target", "identifier", "initial_value", "new_value", "note"]

    body =
      diff
      |> Enum.map(fn m ->
        [
          Map.get(m, :id),
          Map.get(m, :file),
          Map.get(m, :action),
          Map.get(m, :target),
          m |> Map.get(:identifier) |> Jason.encode!(),
          case m |> Map.get(:initial_value) do
            nil -> nil
            arg -> arg |> Jason.encode!()
          end,
          case m |> Map.get(:new_value) do
            nil -> nil
            arg -> arg |> Jason.encode!()
          end,
          Map.get(m, :note)
        ]
      end)

    [headers | body]
    |> CSV.dump_to_stream()
    |> Stream.into(File.stream!(filepath))
    |> Stream.run()
  end

  def apply_delete(file, diff, primary_key) do
    delete_ids =
      diff
      |> Enum.filter(fn d -> d["action"] == "delete" end)
      |> Enum.map(fn d -> d["row_identifier"] |> Jason.decode!() |> Map.fetch!(primary_key) end)

    file |> Enum.reject(fn r -> Map.fetch!(r, primary_key) in delete_ids end)
  end

  def apply_add(file, diff) do
    added_rows =
      diff
      |> Enum.filter(fn d -> d["action"] == "add" end)
      |> Enum.map(fn d -> d["arg"] |> Jason.decode!() end)

    file ++ added_rows
  end

  def apply_update(file, diff, primary_key) do
    updates =
      diff
      |> Enum.filter(fn d -> d["action"] == "update" end)
      |> Enum.map(fn d ->
        {d["row_identifier"] |> Jason.decode!() |> Map.fetch!(primary_key), d["arg"] |> Jason.decode!()}
      end)
      |> Enum.into(%{})

    update_keys = updates |> Map.keys()

    file
    |> Enum.map(fn row ->
      id = row[primary_key]

      if id in update_keys do
        changes = updates |> Map.fetch!(id)
        Map.merge(row, changes)
      else
        row
      end
    end)
  end

  def apply_diff(file_name, file, diff) do
    primary_key = primary_key(file_name)

    file
    |> apply_delete(diff, primary_key)
    |> apply_add(diff)
    |> apply_update(diff, primary_key)
  end

  def dump_file(existing_headers, file) do
    headers =
      file
      |> Enum.flat_map(&Map.keys/1)
      |> MapSet.new()
      |> Enum.to_list()

    new_headers = headers -- existing_headers

    # put the new columns at the end
    output_headers = existing_headers ++ new_headers

    body =
      file
      |> Enum.map(fn m ->
        output_headers |> Enum.map(fn header -> Map.get(m, header) end)
      end)

    ([output_headers] ++ body)
    |> CSV.dump_to_iodata()
    |> IO.iodata_to_binary()
  end

  defp list_entries(unzip, profile) do
    files = files_to_analyze(profile)
    unzip |> Unzip.list_entries() |> Enum.map(&Map.get(&1, :file_name)) |> Enum.filter(fn elm -> elm in files end)
  end

  def files_to_analyze(profile) do
    case profile do
      "core" ->
        ["agency.txt", "calendar.txt", "calendar_dates.txt", "feed_info.txt", "routes.txt", "stops.txt", "trips.txt"]

      "full" ->
        Map.keys(@primary_keys)

      _ ->
        []
    end
  end
end
