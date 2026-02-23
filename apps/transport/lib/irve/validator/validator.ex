defmodule Transport.IRVE.Validator do
  @moduledoc """
  Central entry point for IRVE file validation (currently working on `DataFrame`).
  """

  require Explorer.Series

  def compute_validation(%Explorer.DataFrame{} = df) do
    schema = Transport.IRVE.StaticIRVESchema.schema_content()

    df
    |> Transport.IRVE.Validator.DataFrameValidation.setup_computed_field_validation_columns(schema)
    |> Transport.IRVE.Validator.DataFrameValidation.setup_computed_row_validation_column()
  end

  @doc """
  Validate an IRVE file located at `path`, returning a DataFrame with validation results.
  This wrapper includes some pre-processing steps before actual validation.
  These preprocessing steps do not output any warning and are silent,
  so files that are not strictly valid may be considered as valid without any notice by this function.
  If you want to call a strict validator (no preprocessing), use `compute_validation/1` instead.
  """

  def validate(path, extension \\ ".csv") do
    # NOTE: for now, load the body in memory, because refactoring to get full streaming
    # is too involved for the current sprint deadline.
    body = File.read!(path)
    Transport.IRVE.RawStaticConsolidation.run_cheap_blocking_checks(body, extension)
    # TODO: accumulate warnings
    body = Transport.IRVE.RawStaticConsolidation.ensure_utf8(body)
    # TODO: accumulate warnings

    body
    |> Transport.IRVE.Processing.read_as_uncasted_data_frame()
    |> ensure_uniqueness_of_id_pdc_itinerance()
    |> compute_validation()
  end

  @doc """
  Says from the dataframe output of compute_validation/1 if all rows are valid.
  """
  def full_file_valid?(%Explorer.DataFrame{} = df) do
    df["check_row_valid"]
    |> Explorer.Series.all?()
  end

  @doc """
  iex> df = Explorer.DataFrame.new(%{"id_pdc_itinerance" => ["FRPAN99E87654321", "FRPAN99E87654321", "Non concerné", nil]})
  iex> Transport.IRVE.Validator.ensure_uniqueness_of_id_pdc_itinerance(df)
  ** (RuntimeError) the id_pdc_itinerance column contains duplicates.
  iex> df = Explorer.DataFrame.new(%{"id_pdc_itinerance" => ["FRPAN99E87654321", "FRPAN99E87654322", "Non concerné", "Non concerné", nil, nil]})
  iex> Transport.IRVE.Validator.ensure_uniqueness_of_id_pdc_itinerance(df)
  df
  """
  def ensure_uniqueness_of_id_pdc_itinerance(%Explorer.DataFrame{} = df) do
    # Using count (only on not nil values) and not size, we want the validator to pick nil values afterwards.
    raw_count =
      df["id_pdc_itinerance"]
      |> Explorer.Series.filter(_ != "Non concerné")
      |> Explorer.Series.count()

    distinct_count =
      df["id_pdc_itinerance"]
      |> Explorer.Series.filter(_ != "Non concerné")
      |> Explorer.Series.distinct()
      |> Explorer.Series.count()

    if distinct_count != raw_count do
      raise "the id_pdc_itinerance column contains duplicates, number of duplicates: #{raw_count - distinct_count}. "
    else
      df
    end
  end
end
