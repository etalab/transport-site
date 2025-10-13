defmodule Transport.IRVE.ValidatorTest do
  use ExUnit.Case, async: true

  require Logger

  # TODO: add doctest support, if needed

  def validate(path, callback) do
    # https://hexdocs.pm/explorer/Explorer.DataFrame.html#from_csv/2-options
    options = [
      # set to zero disables inference and default all values to string.
      # this is what we want to keep the input intact & be able to report on its (in)validity
      # "(set to) zero to disable inference and default all values to string"
      infer_schema_length: 0
    ]

    df = Explorer.DataFrame.from_csv!(path, options)

    _schema = Transport.IRVE.StaticIRVESchema.field_names_list()

    [first_line] =
      File.stream!(path)
      |> Enum.take(1)

    # TODO: report error on unsupported delimiter (instead of raising an error like currently)
    delimiter = Transport.IRVE.DataFrame.guess_delimiter!(first_line)

    # we tolerate ";" delimiter, but will report that this is not the way to go
    unless delimiter == "," do
      callback.({:warning, :incorrect_delimiter, delimiter})
    end
  end

  test "hello world" do
    # https://www.data.gouv.fr/datasets/reseau-mobive-reseau-de-recharge-publique-en-nouvelle-aquitaine/
    url = "https://www.data.gouv.fr/api/1/datasets/r/e90f5ccc-dbe3-41bd-8fbb-d64c27ec4e1c"
    path = Path.join(__DIR__, "../../cache-dir/some-data.csv")

    unless File.exists?(path) do
      Logger.info("Downloading file #{path}")
      Req.get!(url, into: File.stream!(path))
    else
      Logger.info("File exist, skipping")
    end

    callback = fn event ->
      IO.inspect(event, IEx.inspect_opts() |> Keyword.put(:label, "Event"))
    end

    validate(path, callback)
  end
end
