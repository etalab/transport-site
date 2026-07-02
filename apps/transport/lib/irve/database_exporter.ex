defmodule Transport.IRVE.DatabaseExporter do
  @moduledoc """
  A module to export IRVE valid PDCs (including duplicates) from the database to a CSV file.
  It first builds a dataframe from the database content, then exports it to CSV.
  """

  import Ecto.Query
  require Explorer.DataFrame

  @export_timeout 90_000
  @chunk_size 10_000

  def export_to_csv(path) do
    build_data_frame() |> Explorer.DataFrame.to_csv!(path)
  end

  @doc """
  Builds a dataframe from the database content, with consistent dtypes with the schema,
  additional file fields, and consolidated coordinates columns.
  The dataframe can then be exported to CSV or passed to the deduplication module.

  Rows are read from the DB and turned into DataFrames chunk by chunk, then concatenated.
  This avoids ever holding the whole result set as a list of Elixir maps at once,
  which may OOM the production server.
  """

  def build_data_frame do
    fields = database_field_list() |> Enum.map(&String.to_atom/1)
    additionnal_file_fields = additional_file_field_list() |> Enum.map(&String.to_atom/1)
    dtypes = chunk_dtypes()

    stream =
      DB.IRVEValidPDC
      |> join(:inner, [p], f in DB.IRVEValidFile, on: p.irve_valid_file_id == f.id)
      |> select([p, f], {map(p, ^fields), map(f, ^additionnal_file_fields)})
      |> DB.Repo.stream(max_rows: @chunk_size)

    {:ok, df} =
      DB.Repo.transact(
        fn ->
          chunks =
            stream
            |> Stream.map(&Map.merge(elem(&1, 0), elem(&1, 1)))
            |> Stream.chunk_every(@chunk_size)
            |> Enum.map(&chunk_to_dataframe(&1, dtypes))

          result =
            case chunks do
              [] -> Explorer.DataFrame.new([], dtypes: dtypes)
              chunks -> Explorer.DataFrame.concat_rows(chunks)
            end

          {:ok, result}
        end,
        timeout: @export_timeout
      )

    df
  end

  defp chunk_dtypes do
    Transport.IRVE.DataFrame.schema_dtypes() ++
      [
        consolidated_is_lon_lat_correct: :boolean,
        datagouv_dataset_id: :string,
        datagouv_resource_id: :string,
        dataset_title: :string,
        datagouv_organization_or_owner: :string
      ]
  end

  # Build a chunk into its final, export-ready shape. Doing this per chunk (rather than once after
  # `concat_rows/1`) is also what keeps the chunks compatible.
  # We pass the dtypes of the schema, and `mutate_coordinates_columns/1` casts
  # the `:decimal` coordinates to a fixed scale and drops the raw `longitude`/`latitude`, whose
  # per-chunk inferred scale (`{:decimal, 38, 16}` vs `{:decimal, 38, 17}`, …) could otherwise make
  # `concat_rows/1` reject the chunks.
  defp chunk_to_dataframe(rows, dtypes) do
    rows
    |> Explorer.DataFrame.new(dtypes: dtypes)
    |> mutate_coordinates_columns()
    # Reorder columns (Map merge got them alphabetically ordered)
    |> Explorer.DataFrame.select(export_field_list())
  end

  def mutate_coordinates_columns(df) do
    df
    |> Explorer.DataFrame.mutate(
      consolidated_longitude: cast(longitude, {:decimal, 10, 5}),
      consolidated_latitude: cast(latitude, {:decimal, 10, 5})
    )
    |> Explorer.DataFrame.discard(["longitude", "latitude"])
    |> Explorer.DataFrame.mutate(
      coordonneesXY: "[" <> cast(consolidated_longitude, :string) <> ", " <> cast(consolidated_latitude, :string) <> "]"
    )
  end

  def database_field_list do
    Transport.IRVE.StaticIRVESchema.field_names_list()
    |> Enum.reject(&(&1 == "coordonneesXY"))
    |> Enum.concat(["longitude", "latitude", "consolidated_is_lon_lat_correct"])
  end

  def additional_file_field_list do
    [
      "datagouv_dataset_id",
      "datagouv_resource_id",
      "dataset_title",
      "datagouv_organization_or_owner",
      "datagouv_last_modified"
    ]
  end

  @doc """
  Returns the list and order of fields to be exported in the dataframe (and CSV file).
  This function is also used for grouping fully identical entries in the deduplication module
  as Explorer’s group_by needs a list of columns (or a function).
  """
  def export_field_list do
    Transport.IRVE.StaticIRVESchema.field_names_list()
    |> Enum.concat(["consolidated_longitude", "consolidated_latitude", "consolidated_is_lon_lat_correct"])
    |> Enum.concat(additional_file_field_list())
  end
end
