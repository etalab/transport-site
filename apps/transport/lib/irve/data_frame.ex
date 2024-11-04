defmodule Transport.IRVE.DataFrame do
  @moduledoc """
  Tooling supporting the parsing of an IRVE static file into `Explorer.DataFrame`
  """

  @doc """
  Helper function to convert TableSchema types into DataFrame ones.

  There is no attempt to make this generic at this point, it is focusing solely
  on the static IRVE use.

  iex> Transport.IRVE.DataFrame.remap_schema_type(:geopoint)
  :string
  iex> Transport.IRVE.DataFrame.remap_schema_type(:number)
  {:u, 16}
  iex> Transport.IRVE.DataFrame.remap_schema_type(:literally_anything)
  :literally_anything
  """
  def remap_schema_type(input_type) do
    case input_type do
      :geopoint -> :string
      :number -> {:u, 16}
      type -> type
    end
  end

  @doc """
  Parse an in-memory binary of CSV content into a typed `Explorer.DataFrame` for IRVE use.
  """
  def dataframe_from_csv_body!(body, schema \\ Transport.IRVE.StaticIRVESchema.schema_content()) do
    dtypes =
      schema
      |> Map.fetch!("fields")
      |> Enum.map(fn %{"name" => name, "type" => type} ->
        {String.to_atom(name), String.to_atom(type) |> Transport.IRVE.DataFrame.remap_schema_type()}
      end)

    Explorer.DataFrame.load_csv!(body, dtypes: dtypes)
  end
end
