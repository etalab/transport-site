defmodule Transport.Validators.NeTEx.ResultsAdapters.Commons do
  @moduledoc """
  Collection of helpers to be used by all results adapters.
  """
  require Explorer.DataFrame, as: DF
  alias Explorer.Series, as: S

  @dtypes [
    category: :category,
    code: :category,
    criticity: :category,
    message: :string,
    "resource.class": :category,
    "resource.column": {:u, 8},
    "resource.filename": :category,
    "resource.id": :string,
    "resource.line": {:u, 16}
  ]

  def to_dataframe(errors, extra_attributes_fun) do
    errors
    |> Enum.map(&project_error(&1, extra_attributes_fun))
    |> DF.new(dtypes: @dtypes)
  end

  defp project_error(entry, extra_attributes_fun) do
    mandatory_attributes = build_mandatory_attributes(entry)

    resource = Map.get(entry, "resource", %{})

    mandatory_attributes
    |> Map.merge(build_resource_attributes(resource))
    |> Map.merge(extra_attributes_fun.(mandatory_attributes))
  end

  defp build_mandatory_attributes(entry) do
    %{
      "code" => "unknown-code",
      "criticity" => "error",
      "message" => "Unknown error"
    }
    |> build_with_default_attributes(entry)
  end

  defp build_resource_attributes(resource) do
    %{
      "resource.id" => nil,
      "resource.line" => nil,
      "resource.class" => nil,
      "resource.column" => nil,
      "resource.filename" => nil
    }
    |> build_with_default_attributes(prefix_keys(resource, "resource."))
  end

  defp prefix_keys(map, prefix) do
    rename_keys(map, fn key -> "#{prefix}#{key}" end)
  end

  defp rename_keys(map, fun) do
    map
    |> Map.to_list()
    |> Enum.map(fn {key, value} -> {fun.(key), value} end)
    |> Map.new()
  end

  defp build_with_default_attributes(defaults, attributes) do
    Map.merge(defaults, Map.intersect(defaults, attributes))
  end

  def to_binary(%Explorer.DataFrame{} = df) do
    DF.dump_parquet!(df, compression: :brotli)
  end

  def from_binary(binary) when is_binary(binary) do
    DF.load_parquet!(binary)
  end

  def slice(df, %Scrivener.Config{} = config) do
    df
    |> DF.slice(page(config))
    |> DF.select(["code", "criticity", "message", "resource.filename", "resource.line"])
    |> DF.to_rows()
  end

  defp page(%Scrivener.Config{} = config) do
    first = (config.page_number - 1) * config.page_size
    last = config.page_number * config.page_size - 1
    Range.new(first, last)
  end

  def to_issues(entries), do: Enum.map(entries, &to_issue/1)

  defp to_issue(%{} = entry) do
    %{
      "code" => entry["code"],
      "message" => entry["message"],
      "criticity" => entry["criticity"],
      "resource" =>
        %{
          "filename" => entry["resource.filename"],
          "line" => entry["resource.line"]
        }
        |> drop_empty_values()
    }
    |> drop_empty_values()
  end

  def drop_empty_values(map), do: Map.filter(map, fn {_key, value} -> value != %{} and not is_nil(value) end)

  def get_values(%Explorer.DataFrame{} = df, column) do
    df
    |> DF.distinct([column])
    |> DF.to_rows()
    |> Enum.map(& &1[column])
  end

  def count_and_slice(%Explorer.DataFrame{} = df, pagination_config) do
    total_count = S.count(df["code"])

    issues =
      df
      |> slice(pagination_config)
      |> to_issues()

    {total_count, issues}
  end
end
