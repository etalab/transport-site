defmodule Transport.IRVE.ValidatorTest do
  use ExUnit.Case, async: true

  require Logger

  def compute_validation_fields(%Explorer.DataFrame{} = df, %{} = schema, validation_callback) do
    fields =
      Map.fetch!(schema, "fields")
      |> Enum.take(1)

    Enum.reduce(fields, df, fn field, df ->
      handle_one_schema_field(df, field, validation_callback)
    end)
  end

  def handle_one_schema_field(%Explorer.DataFrame{} = df, %{} = field, validation_callback) do
    field =
      field
      |> Map.delete("description")
      |> Map.delete("example")

    # unpack the field def completely, raising on whatever remains (to protect from unhandled cases)
    {name, field} = Map.pop!(field, "name")
    {type, field} = Map.pop!(field, "type")
    {optional_format, field} = Map.pop(field, "format")
    {constraints, rest_of_field} = Map.pop!(field, "constraints")

    if rest_of_field != %{} do
      raise("Field def contains extra stuff ; please review\n#{rest_of_field |> inspect(pretty: true)}")
    end

    # at this point, the whole field definition is exploded, in full, toward specific variables, so
    # we can now work efficiently at computing validation columns for each field in the input schema
    configure_computations_for_one_schema_field(df, name, type, optional_format, constraints, validation_callback)
  end

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        "nom_amenageur" = name,
        "string" = type,
        nil = _format,
        constraints,
        validation_callback
      ) do
    IO.puts("Configuring field checks: #{name}")

    # nothing to do
    assert constraints == %{"required" => false}

    df
  end

  @test_resources [
    %{
      # https://www.data.gouv.fr/datasets/reseau-mobive-reseau-de-recharge-publique-en-nouvelle-aquitaine/
      label: "Mobive (séparateur ;)",
      url: "https://www.data.gouv.fr/api/1/datasets/r/e90f5ccc-dbe3-41bd-8fbb-d64c27ec4e1c"
    }
    # TODO: add a latin1 case
    # TODO: report on non CSV data (e.g. zip, reusing the quick probe I implemented)
    # TODO: add a case with extraneous columns (but nothing problematic)
    # TODO: add a case with duplicate columns (maybe, if any)
    # TODO: add a case with completely broken columns
    # TODO: add a case with unsupported separator (e.g. `\t`)
    # TODO: identify more cases as handled by the raw consolidation, evaluate them, see if we need to cover them or not
  ]

  @cache_dir Path.join(__DIR__, "../../cache-dir")

  def setup do
    if !File.exists?(@cache_dir), do: File.mkdir!(@cache_dir)
  end

  test "hello world" do
    @test_resources
    |> Enum.each(fn %{label: label, url: url} ->
      path = Path.join(@cache_dir, Path.basename(url))

      if File.exists?(path) do
        Logger.info("File #{path} exist, skipping")
      else
        Logger.info("Downloading #{url} to file #{path}")
        Req.get!(url, into: File.stream!(path))
      end

      callback = fn event ->
        IO.inspect(event, IEx.inspect_opts() |> Keyword.put(:label, "Event"))
      end

      IO.puts("Running #{label |> inspect} through the validator...")
      validate(path, callback)
    end)
  end
end
