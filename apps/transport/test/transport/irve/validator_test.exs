defmodule Transport.IRVE.ValidatorTest do
  use ExUnit.Case, async: true

  require Logger

  # TODO: add doctest support, if needed

  def validate(path, validation_callback) do
    [file_first_line] =
      File.stream!(path)
      |> Enum.take(1)

    # determine if we have an acceptable delimiter, or not
    delimiter =
      try do
        Transport.IRVE.DataFrame.guess_delimiter!(file_first_line)
      rescue
        e in Transport.IRVE.DataFrame.ColumnDelimiterGuessError ->
          validation_callback.({:error, :unsupported_delimiter, e})
          reraise e, __STACKTRACE__
      end

    # only "," and ";" are supported. othercases will normally raise above, or
    # worst case result in `case` failure here
    case delimiter do
      "," ->
        # best case - no warnings, we're good, do nothing!
        validation_callback.({:info, :best_delimiter_found})
        true

      ";" ->
        # we're accepting it, but that's not what is normally expected, signal it
        validation_callback.({:warning, :incorrect_delimiter, delimiter})
        validation_callback.({:info, :applying_delimiter_tweak, delimiter})
    end

    # https://hexdocs.pm/explorer/Explorer.DataFrame.html#from_csv/2-options
    options = [
      # set to zero disables inference and default all values to string.
      # this is what we want to keep the input intact & be able to report on its (in)validity
      # "(set to) zero to disable inference and default all values to string"
      infer_schema_length: 0,
      delimiter: delimiter
    ]

    df = Explorer.DataFrame.from_csv!(path, options)

    columns = Explorer.DataFrame.names(df)
    # exact comparison (MUST in the spec), in the exact same order
    if columns != Transport.IRVE.StaticIRVESchema.field_names_list() do
      # NOTE: this could lead to a non-blocking warning (such as "we have extra columns, this is not recommended, but we'll take your file for now")
      # or to harder stuff (e.g. "you have duplicates, please fix this, we won't go forward")
      validation_callback.({:error, :invalid_columns, "TO BE SPECIFIED & SPLIT IN SEPARATE CASES"})
    else
      validation_callback.({:info, :columns_are_valid_yay})
      validation_callback.({:info, :file_is_valid_at_this_point})
    end
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
