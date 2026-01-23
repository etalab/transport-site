defmodule Transport.IRVE.DatabaseExporter do
  @moduledoc """
  A module to export IRVE valid PDCs (including duplicates) from the database to a CSV file.
  It first builds a dataframe from the database content, then exports it to CSV.
  """

  import Ecto.Query

  @export_timeout 90_000

  def export_to_csv(path) do
    build_data_frame() |> Explorer.DataFrame.to_csv!(path)
  end

  def build_data_frame do
    fields = main_schema_field_list() |> Enum.map(&String.to_atom/1)
    additionnal_file_fields = additional_file_field_list() |> Enum.map(&String.to_atom/1)

    stream =
      DB.IRVEValidPDC
      |> join(:inner, [p], f in DB.IRVEValidFile, on: p.irve_valid_file_id == f.id)
      |> select([p, f], {map(p, ^fields), map(f, ^additionnal_file_fields)})
      |> DB.Repo.stream()

    {:ok, df} =
      DB.Repo.transact(
        fn ->
          result =
            stream
            |> Stream.map(&Map.merge(elem(&1, 0), elem(&1, 1)))
            |> Enum.into([])
            |> Explorer.DataFrame.new()

          {:ok, result}
        end,
        timeout: @export_timeout
      )

    # Reorder columns (Map merge got them alphabeltically ordered)
    df |> Explorer.DataFrame.select(main_schema_field_list() ++ additional_file_field_list())
  end

  def main_schema_field_list do
    Transport.IRVE.StaticIRVESchema.field_names_list()
    |> Enum.reject(&(&1 == "coordonneesXY"))
    |> Enum.concat(["longitude", "latitude"])
  end

  def additional_file_field_list do
    ["dataset_datagouv_id", "resource_datagouv_id"]
  end
end
