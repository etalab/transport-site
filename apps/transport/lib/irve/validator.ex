defmodule Transport.IRVE.Validator do
  require Logger

  @moduledoc """
  This modules implements a validator for the static IRVE file format (see `schema-irve-statique.json`).

  It aims to comply with:
  - a subset of the `TableSchema` specification https://specs.frictionlessdata.io/table-schema/
  - and for only the static IRVE schema at this point
  """

  def validate(file_path) do
    schema = Transport.IRVE.StaticIRVESchema.schema_content()

    callback = fn
      # an error is blocking - we just exit right away
      {:fatal_error, _error_type, _error_details} = event ->
        IO.inspect(event, IEx.inspect_opts() |> Keyword.put(:label, "Event"))
        throw(:fatal_validation_error)

      {:info, _msg} = event ->
        IO.inspect(event, IEx.inspect_opts() |> Keyword.put(:label, "Event"))
    end

    try do
      Logger.info("Validating IRVE static file at #{file_path}")
      delimiter = guess_supported_column_separator!(file_path, callback)
      df = load_dataframe!(file_path, delimiter)
      verify_columns!(df, schema, callback)
      # at this point we should have exactly the columns required
      df = setup_column_checks(df, schema)
      df = setup_row_check(df)

      stats = compute_row_validity_stats(df)

      %{
        # provide an aggregate
        file_valid: stats.row_invalid_count == 0,
        # help me during tests for now
        row_stats: stats,
        df: df
      }
    catch
      :fatal_validation_error ->
        # TODO: bubble up the exact reason, since the file was not processed
        %{
          file_valid: false
        }
    end
  end

  @doc """
  Compute row stats (number of valid / invalid / total row count)
  """
  def compute_row_validity_stats(%Explorer.DataFrame{} = df, column_name \\ "check_row_valid") do
    values =
      df
      |> Explorer.DataFrame.frequencies([column_name])
      |> Explorer.DataFrame.to_rows()

    f = fn c_name, bool ->
      values
      |> Enum.find(%{"counts" => 0}, &(&1[c_name] == bool))
      |> Map.fetch!("counts")
    end

    result = %{
      row_valid_count: a = f.(column_name, true),
      row_invalid_count: b = f.(column_name, false)
    }

    Map.put(result, :row_total_count, a + b)
  end

  def guess_supported_column_separator!(file_path, validation_callback) do
    [file_first_line] =
      File.stream!(file_path)
      |> Enum.take(1)

    # determine if we have an acceptable delimiter, or not
    delimiter =
      try do
        Transport.IRVE.DataFrame.guess_delimiter!(file_first_line)
      rescue
        e in Transport.IRVE.DataFrame.ColumnDelimiterGuessError ->
          validation_callback.({:fatal_error, :unsupported_delimiter, e})
      end

    # only "," and ";" are supported. othercases will normally raise above, or
    # worst case result in `case` failure here
    case delimiter do
      "," ->
        # best case - no warnings, we're good, do nothing!
        true

      ";" ->
        # we're accepting it, but that's not what is normally expected, signal it
        validation_callback.({:warning, :delimiter_correction_applied, delimiter})
    end

    delimiter
  end

  def load_dataframe!(file_path, delimiter) do
    # https://hexdocs.pm/explorer/Explorer.DataFrame.html#from_csv/2-options
    options = [
      # set to zero disables inference and default all values to string.
      # this is what we want to keep the input intact & be able to report on its (in)validity
      # "(set to) zero to disable inference and default all values to string"
      infer_schema_length: 0,
      delimiter: delimiter
    ]

    Explorer.DataFrame.from_csv!(file_path, options)
  end

  def verify_columns!(%Explorer.DataFrame{} = df, schema, validation_callback) do
    schema_columns = Transport.IRVE.StaticIRVESchema.field_names_list(schema)
    columns = Explorer.DataFrame.names(df)
    # exact comparison (MUST in the spec), in the exact same order
    if columns != schema_columns do
      # NOTE: this could lead to a non-blocking warning (such as "we have extra columns, this is not recommended, but we'll take your file for now")
      # or to harder stuff (e.g. "you have duplicates, please fix this, we won't go forward")
      validation_callback.({:fatal_error, :invalid_columns, "TO BE SPECIFIED & SPLIT IN SEPARATE CASES"})
    end
  end

  def setup_column_checks(%Explorer.DataFrame{} = df, schema) do
    schema
    |> Map.fetch!("fields")
    |> Enum.reduce(df, fn field_definition, df ->
      # mandatory
      field_name = field_definition |> Map.fetch!("name")
      field_type = field_definition |> Map.fetch!("type")
      field_constraints = field_definition |> Map.fetch!("constraints")
      # optional
      field_format = field_definition["format"]

      # TODO: assert that nothing is left in the def

      case field_name do
        n
        when n in [
               "nom_amenageur",
               "siren_amenageur",
               "contact_amenageur",
               "nom_operateur",
               "contact_operateur",
               "telephone_operateur",
               "nom_enseigne",
               "id_station_itinerance",
               "id_station_local",
               "nom_station",
               "implantation_station",
               "adresse_station",
               "code_insee_commune",
               "coordonneesXY",
               "nbre_pdc"
             ] ->
          configure_computations_for_one_schema_field(df, field_name, field_type, field_format, field_constraints)

        # do nothing
        _ ->
          df
      end
    end)
  end

  @doc """
  Grab all the `check_column_xyz` fields, and build a `and` operation between all of them.
  """
  def setup_row_check(%Explorer.DataFrame{} = df) do
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

  import ExUnit.Assertions

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        "nom_amenageur" = name,
        "string" = _type,
        nil = _format,
        constraints
      ) do
    assert constraints == %{"required" => false}

    Explorer.DataFrame.mutate_with(df, fn df ->
      %{
        "check_column_nom_amenageur_valid" => true
      }
    end)
  end

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        "siren_amenageur" = name,
        "string" = _type,
        nil = _format,
        constraints
      ) do
    pattern = "^\\d{9}$"

    # debugging assertions for now, will be removable later
    assert constraints == %{"pattern" => pattern, "required" => false}

    # either the field is empty (and we don't need to check the pattern),
    # or it has a value (in which case the value must comply with the pattern)
    Explorer.DataFrame.mutate_with(df, fn df ->
      # NOTE: this does not explain why the cell is invalid, when it is invalid
      # We'll need to store each check result to be able to report on that.
      # either using separate columns, or a complex type if needed or better & not memory hungry.
      # I will experiment with a field requiring more logic
      %{
        "check_column_siren_amenageur_valid" =>
          Explorer.Series.or(
            df[name]
            |> Explorer.Series.strip()
            |> Explorer.Series.fill_missing("")
            |> Explorer.Series.equal(""),
            Explorer.Series.re_contains(df[name], pattern)
          )
      }
    end)
  end

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        "contact_amenageur" = name,
        "string" = _type,
        "email" = _format,
        constraints
      ) do
    # # debugging assertions for now, will be removable later
    assert constraints == %{"required" => false}

    # TODO: reuse primitives instead, but they'll need a rework before this is doable.
    Explorer.DataFrame.mutate_with(df, fn df ->
      %{
        "check_column_contact_amenageur_valid" =>
          Explorer.Series.or(
            df[name]
            |> Explorer.Series.strip()
            |> Explorer.Series.fill_missing("")
            |> Explorer.Series.equal(""),
            Explorer.Series.re_contains(df[name], Transport.IRVE.Validation.Primitives.simple_email_pattern())
          )
      }
    end)
  end

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        "nom_operateur" = _name,
        "string" = _type,
        nil = _format,
        constraints
      ) do
    assert constraints == %{"required" => false}

    Explorer.DataFrame.mutate_with(df, fn df ->
      %{
        "check_column_nom_operateur_valid" => true
      }
    end)
  end

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        "contact_operateur" = name,
        "string" = _type,
        "email" = _format,
        constraints
      ) do
    assert constraints == %{"required" => true}

    Explorer.DataFrame.mutate_with(df, fn df ->
      %{
        "check_column_contact_operateur_valid" =>
          Explorer.Series.and(
            df[name]
            |> Explorer.Series.strip()
            |> Explorer.Series.fill_missing("")
            |> Explorer.Series.not_equal(""),
            Explorer.Series.re_contains(df[name], Transport.IRVE.Validation.Primitives.simple_email_pattern())
          )
      }
    end)
  end

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        "telephone_operateur" = _name,
        "string" = _type,
        nil = _format,
        constraints
      ) do
    assert constraints == %{"required" => false}

    Explorer.DataFrame.mutate_with(df, fn df ->
      %{
        "check_column_telephone_operateur_valid" => true
      }
    end)
  end

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        "nom_enseigne" = name,
        "string" = _type,
        nil = _format,
        constraints
      ) do
    assert constraints == %{"required" => true}

    Explorer.DataFrame.mutate_with(df, fn df ->
      %{
        "check_column_nom_enseigne_valid" =>
          df[name]
          |> Explorer.Series.strip()
          |> Explorer.Series.fill_missing("")
          |> Explorer.Series.not_equal("")
      }
    end)
  end

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        "id_station_itinerance" = name,
        "string" = _type,
        nil = _format,
        constraints
      ) do
    pattern = ~S/(?:(?:^|,)(^[A-Z]{2}[A-Z0-9]{4,33}$|Non concerné))+$/
    assert constraints == %{"required" => true, "pattern" => pattern}

    Explorer.DataFrame.mutate_with(df, fn df ->
      %{
        "check_column_id_station_itinerance_valid" =>
          Explorer.Series.and(
            df[name]
            |> Explorer.Series.strip()
            |> Explorer.Series.fill_missing("")
            |> Explorer.Series.not_equal(""),
            Explorer.Series.re_contains(df[name], pattern)
          )
      }
    end)
  end

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        "id_station_local" = _name,
        "string" = _type,
        nil = _format,
        constraints
      ) do
    assert constraints == %{"required" => false}

    Explorer.DataFrame.mutate_with(df, fn df ->
      %{
        "check_column_id_station_local_valid" => true
      }
    end)
  end

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        "nom_station" = name,
        "string" = _type,
        nil = _format,
        constraints
      ) do
    assert constraints == %{"required" => true}

    Explorer.DataFrame.mutate_with(df, fn df ->
      %{
        "check_column_nom_station_valid" =>
          df[name]
          |> Explorer.Series.strip()
          |> Explorer.Series.fill_missing("")
          |> Explorer.Series.not_equal("")
      }
    end)
  end

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        "implantation_station" = name,
        "string" = _type,
        nil = _format,
        constraints
      ) do
    enum_values = [
      "Voirie",
      "Parking public",
      "Parking privé à usage public",
      "Parking privé réservé à la clientèle",
      "Station dédiée à la recharge rapide"
    ]

    assert constraints == %{"required" => true, "enum" => enum_values}

    Explorer.DataFrame.mutate_with(df, fn df ->
      %{
        "check_column_implantation_station_valid" =>
          Explorer.Series.and(
            df[name]
            |> Explorer.Series.strip()
            |> Explorer.Series.fill_missing("")
            |> Explorer.Series.not_equal(""),
            df[name] |> Explorer.Series.in(enum_values)
          )
      }
    end)
  end

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        "adresse_station" = name,
        "string" = _type,
        nil = _format,
        constraints
      ) do
    assert constraints == %{"required" => true}

    Explorer.DataFrame.mutate_with(df, fn df ->
      %{
        "check_column_adresse_station_valid" =>
          df[name]
          |> Explorer.Series.strip()
          |> Explorer.Series.fill_missing("")
          |> Explorer.Series.not_equal("")
      }
    end)
  end

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        "code_insee_commune" = name,
        "string" = _type,
        nil = _format,
        constraints
      ) do
    pattern = ~S/^([013-9]\d|2[AB1-9])\d{3}$/
    assert constraints == %{"required" => false, "pattern" => pattern}

    Explorer.DataFrame.mutate_with(df, fn df ->
      %{
        "check_column_code_insee_commune_valid" =>
          Explorer.Series.or(
            df[name]
            |> Explorer.Series.strip()
            |> Explorer.Series.fill_missing("")
            |> Explorer.Series.equal(""),
            Explorer.Series.re_contains(df[name], pattern)
          )
      }
    end)
  end

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        "coordonneesXY" = name,
        "geopoint" = _type,
        "array" = _format,
        constraints
      ) do
    assert constraints == %{"required" => true}

    geopoint_pattern = ~S/\A\[\-?\d+(\.\d+)?,\s?\-?\d+(\.\d+)?\]\z/

    Explorer.DataFrame.mutate_with(df, fn df ->
      %{
        "check_column_coordonneesXY_valid" =>
          Explorer.Series.and(
            df[name]
            |> Explorer.Series.strip()
            |> Explorer.Series.fill_missing("")
            |> Explorer.Series.not_equal(""),
            Explorer.Series.re_contains(df[name], geopoint_pattern)
          )
      }
    end)
  end

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        "nbre_pdc" = name,
        "integer" = _type,
        nil = _format,
        constraints
      ) do
    assert constraints == %{"required" => true, "minimum" => 0}

    Explorer.DataFrame.mutate_with(df, fn df ->
      casted = df[name] |> Explorer.Series.cast(:integer)

      %{
        "check_column_nbre_pdc_valid" =>
          Explorer.Series.and(
            Explorer.Series.is_not_nil(casted),
            Explorer.Series.greater_equal(casted, 0)
          )
      }
    end)
  end
end
