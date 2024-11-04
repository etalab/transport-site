defmodule Transport.IRVE.DataFrame do
  @moduledoc """
  A module providing programmatic access to the static IRVE schema,
  as stored in the source code.
  """

  # TODO: move to dedicated module.
  # TODO: consider grouping this (see unlock dynamic equivalent)
  def schema_content do
    __ENV__.file
    |> Path.join("../../../../shared/meta/schema-irve-statique.json")
    |> Path.expand()
    |> File.read!()
    |> Jason.decode!()
  end

  def remap_schema_type(input_type) do
    case input_type do
      # TODO: extract individual coordinates
      :geopoint -> :string
      # works for this specific case
      :number -> {:u, 16}
      type -> type
    end
  end

  def dataframe_from_csv_body!(body) do
    dtypes =
      schema_content()
      |> Map.fetch!("fields")
      |> Enum.map(fn %{"name" => name, "type" => type} ->
        {String.to_atom(name), String.to_atom(type) |> Transport.IRVE.DataFrame.remap_schema_type()}
      end)

    Explorer.DataFrame.load_csv!(body, dtypes: dtypes)
  end
end
