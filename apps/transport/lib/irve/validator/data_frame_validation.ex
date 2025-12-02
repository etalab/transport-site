defmodule Transport.IRVE.Validator.DataFrameValidation do
  @moduledoc """
  Once a file has been loaded & corrected for various file-level
  issues (delimiters, encoding), it becomes possible to analyze
  the data it contains as a whole, and build "validation series".

  This is what this module does, leveraging `Transport.IRVE.Validator.FieldValidation`.

  Logic:
  - for each field in `Transport.IRVE.StaticIRVESchema`, setup a `check_$column_name$_valid`
    boolean series, handling everything that is defined in the schema for that specific field. This
    includes "requiredness" of the field, field type, constraints, format, everything.
  - for each row in the data frame, setup a `check_row_valid` indicating if the row itself is valid,
    doing a logic `AND` between all the field-level checks described above
  """

  def setup_computed_field_validation_columns(%Explorer.DataFrame{} = df, schema) do
    schema
    |> Map.fetch!("fields")
    |> Enum.reduce(df, fn field_definition, df ->
      {field_name, field_type, field_format, field_constraints} = extract_field_definition_data!(field_definition)
      setup_computed_field_validation_column(df, field_name, field_type, field_format, field_constraints)
    end)
  end

  @doc """
  Process ("explode") a TableSchema field definition.
  Raise an error if an unexpected part is present, for safety.
  """
  def extract_field_definition_data!(field_def) do
    # mandatory parts
    {name, field_def} = Map.pop!(field_def, "name")
    {type, field_def} = Map.pop!(field_def, "type")
    {constraints, field_def} = Map.pop!(field_def, "constraints")

    # optional part
    {format, field_def} = Map.pop(field_def, "format")

    # warn us (hard fail) if something has been added to the schema
    0 = map_size(field_def |> Map.delete("description") |> Map.delete("example"))

    # we can now safely return, everything that existed has been processed
    {name, type, format, constraints}
  end

  def setup_computed_field_validation_column(
        %Explorer.DataFrame{} = df,
        field_name,
        type,
        format,
        constraints
      ) do
    {required, validation_constraints} = Map.pop!(constraints, "required")

    Explorer.DataFrame.mutate_with(df, fn df ->
      validation_series =
        Transport.IRVE.Validator.FieldValidation.column_valid?(df, field_name, type, format, validation_constraints)

      final_validation =
        Transport.DataFrame.RequirednessProcessing.wrap_with_requiredness(df[field_name], validation_series,
          required: required
        )

      %{"check_column_#{field_name}_valid" => final_validation}
    end)
  end

  @doc """
  Grab all the `check_column_xyz` fields, and build a `and` operation between all of them.
  """
  def setup_computed_row_validation_column(%Explorer.DataFrame{} = df) do
    df
    |> Explorer.DataFrame.mutate_with(fn df ->
      row_valid =
        df
        |> Explorer.DataFrame.names()
        |> Enum.filter(&String.starts_with?(&1, "check_column_"))
        |> Enum.map(&df[&1])
        |> Enum.reduce(&Explorer.Series.and/2)

      %{"check_row_valid" => row_valid}
    end)
  end
end
