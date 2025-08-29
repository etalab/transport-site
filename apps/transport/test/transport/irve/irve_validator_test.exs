defmodule Transport.IRVE.ValidationTests do
  use ExUnit.Case, async: true
  doctest Transport.IRVE.Validator, import: true

  import Explorer.Series
  import Explorer.DataFrame
  test "works" do
    # let's train on one of the largest files available, from the start.
    file = Path.expand("~/Downloads/irve_static_consolidation.csv")
    # load it, assuming only strings, so we can leverage DataFrame conveniences.
    schema = Transport.IRVE.StaticIRVESchema.schema_content()
    # use the list of fields, but load everything as string, to keep the original
    # data mostly unchanged & leave us the opportunity to run verifications on it.
    dtypes = schema["fields"]
    |> Enum.map(& {&1["name"], :string})

    df = Explorer.DataFrame.from_csv(file, dtypes: dtypes, lazy: true)

    df |> Explorer.DataFrame.estimated_size()
    |> IO.inspect(IEx.inspect_opts)

  end
end
