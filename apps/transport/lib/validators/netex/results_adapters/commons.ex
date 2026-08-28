defmodule Transport.Validators.NeTEx.ResultsAdapters.Commons do
  @moduledoc """
  Collection of helpers to be used by all results adapters.
  """
  require Explorer.DataFrame, as: DF

  @no_error "NoError"

  @doc false
  def xsd_schema_category, do: "xsd-schema"

  @doc false
  def base_rules_category, do: "base-rules"

  @doc false
  def french_profile_category, do: "french-profile"

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
    rows = Enum.map(errors, &project_error(&1, extra_attributes_fun))

    if Enum.empty?(rows) do
      # Create an empty DataFrame with proper column dtypes using keyword list syntax
      DF.new(Enum.map(@dtypes, fn {name, _dtype} -> {name, []} end), dtypes: @dtypes)
    else
      DF.new(rows, dtypes: @dtypes)
    end
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
      "message" => "Unknown error",
      "category" => nil
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

  defp sorted_slice(df, %Scrivener.Config{} = config) do
    df
    |> DF.select(["code", "criticity", "message", "resource.filename", "resource.line"])
    |> DF.mutate(_severity: if(criticity == "error", do: 1, else: if(criticity == "warning", do: 2, else: 3)))
    |> DF.sort_with(
      &[{:asc, &1["_severity"]}, {:asc, &1["resource.filename"]}, {:asc, &1["resource.line"]}, {:asc, &1["message"]}]
    )
    |> DF.discard(:_severity)
    |> DF.slice(page(config))
    |> DF.to_rows()
  end

  defp page(%Scrivener.Config{} = config) do
    first = (config.page_number - 1) * config.page_size
    last = config.page_number * config.page_size - 1
    Range.new(first, last)
  end

  defp to_issues(entries), do: Enum.map(entries, &to_issue/1)

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

  defp drop_empty_values(map), do: Map.filter(map, fn {_key, value} -> value != %{} and not is_nil(value) end)

  def get_values(%Explorer.DataFrame{} = df, column) do
    if has_column?(df, column) do
      df
      |> DF.distinct([column])
      |> DF.to_rows()
      |> Enum.map(& &1[column])
    else
      []
    end
  end

  def count_and_slice(%Explorer.DataFrame{} = df, pagination_config) do
    total_count = DF.n_rows(df)
    issues = df |> sorted_slice(pagination_config) |> to_issues()
    {total_count, issues}
  end

  def has_column?(df, column_name) do
    df
    |> DF.names()
    |> Enum.member?(column_name)
  end

  def summarize_xsd_errors(df) do
    if has_column?(df, "category") do
      df
      |> DF.frequencies(["message"])
      |> DF.sort_by(desc: counts)
      |> DF.to_rows()
    else
      []
    end
  end

  @doc false
  def severity_level(key) do
    case key do
      "error" -> 1
      "warning" -> 2
      "information" -> 3
      _ -> 4
    end
  end

  @doc false
  def get_worst_criticity(_cat_df, 0), do: @no_error

  def get_worst_criticity(cat_df, _count) do
    cat_df
    |> DF.select(:criticity)
    |> DF.distinct([:criticity])
    |> DF.to_rows()
    |> Enum.map(fn %{"criticity" => c} -> c end)
    |> Enum.min_by(&severity_level/1, fn -> @no_error end)
  end

  @doc """
  Computes a category-based summary from a binary (parquet) result.

  Counts only the most severe level per category. Returns all categories
  even when empty (with count 0 and NoError).

  ## Examples

      iex> errors = [%{"code" => "xsd-1", "criticity" => "error", "category" => "xsd-schema"}, %{"code" => "rule-1", "criticity" => "warning", "category" => "base-rules"}]
      iex> df = to_dataframe(errors, fn _ -> %{} end)
      iex> binary = to_binary(df)
      iex> categories = ["xsd-schema", "base-rules"]
      iex> summary_from_binary(binary, categories) |> Enum.map(fn c -> {c["category"], c["stats"]} end)
      [{"xsd-schema", %{"count" => 1, "criticity" => "error"}}, {"base-rules", %{"count" => 1, "criticity" => "warning"}}]
  """
  def summary_from_binary(binary_result, categories_preferred_order) when is_binary(binary_result) do
    df = from_binary(binary_result)

    categories_with_counts =
      if has_column?(df, "category") do
        group_by_category(df)
        |> Map.new(&format_category_stats/1)
      else
        %{}
      end

    categories_preferred_order
    |> Enum.map(fn category ->
      %{
        "category" => category,
        "stats" => Map.get(categories_with_counts, category, %{"count" => 0, "criticity" => @no_error})
      }
    end)
  end

  @doc """
  Computes a category-based summary from a category-keyed map of errors.

  Counts only the most severe level per category. Returns all categories
  even when empty (with count 0 and NoError).

  ## Examples

      iex> errors = %{"xsd-schema" => [%{"code" => "xsd-1", "criticity" => "error"}], "base-rules" => [%{"code" => "rule-1", "criticity" => "warning"}]}
      iex> categories = ["xsd-schema", "base-rules"]
      iex> summary_map_errors(errors, categories) |> Enum.map(fn c -> {c["category"], c["stats"]} end)
      [{"xsd-schema", %{"count" => 1, "criticity" => "error"}}, {"base-rules", %{"count" => 1, "criticity" => "warning"}}]

      iex> summary_map_errors(%{}, ["xsd-schema", "base-rules"])
      [%{"category" => "xsd-schema", "stats" => %{"count" => 0, "criticity" => "NoError"}}, %{"category" => "base-rules", "stats" => %{"count" => 0, "criticity" => "NoError"}}]
  """
  def summary_map_errors(errors, categories_preferred_order) when is_map(errors) do
    categories_with_counts =
      if Enum.empty?(errors) do
        %{}
      else
        errors
        |> Enum.map(fn {category, errs} -> category_stats(category, errs) end)
        |> Map.new()
      end

    categories_preferred_order
    |> Enum.map(fn category ->
      %{
        "category" => category,
        "stats" => Map.get(categories_with_counts, category, %{"count" => 0, "criticity" => @no_error})
      }
    end)
  end

  @doc false
  def category_stats(category, errs) do
    worst_criticity =
      errs
      |> Enum.map(&Map.get(&1, "criticity", @no_error))
      |> Enum.min_by(&severity_level/1, fn -> @no_error end)

    count = Enum.count(errs, &(Map.get(&1, "criticity", @no_error) == worst_criticity))
    {category, %{"count" => count, "criticity" => worst_criticity}}
  end

  @doc false
  defp group_by_category(df) do
    if Explorer.Series.count(df["code"]) == 0 do
      %{}
    else
      df
      |> DF.frequencies(["category", "criticity"])
      |> DF.to_rows()
      |> Enum.group_by(& &1["category"])
      |> Map.new(&group_row_stats/1)
    end
  end

  defp group_row_stats({category, rows}) do
    worst_criticity =
      rows
      |> Enum.map(& &1["criticity"])
      |> Enum.min_by(&severity_level/1, fn -> @no_error end)

    counts =
      rows
      |> Map.new(fn %{"criticity" => c, "counts" => n} -> {c, n} end)

    {category, %{worst: worst_criticity, counts: counts}}
  end

  defp format_category_stats({category, %{worst: worst, counts: counts}}) do
    {category, %{"count" => Map.get(counts, worst, 0), "criticity" => worst}}
  end

  @doc "Flattens a category-keyed map of errors into a single list."
  def flatten_map_errors(errors) when is_map(errors) do
    errors
    |> Map.values()
    |> List.flatten()
  end

  @doc """
  Computes per-category, per-severity counts from a binary (parquet) result.

  Returns `%{"category" => %{"error" => N, "warning" => M}}`.
  Categories with no rows are omitted.

  ## Examples

      iex> errors = [%{"code" => "xsd-1", "criticity" => "error", "category" => "xsd-schema"}, %{"code" => "rule-1", "criticity" => "warning", "category" => "base-rules"}]
      iex> df = to_dataframe(errors, fn _ -> %{} end)
      iex> binary = to_binary(df)
      iex> count_by_category_and_severity(binary)
      %{"xsd-schema" => %{"error" => 1}, "base-rules" => %{"warning" => 1}}
  """
  @doc since: "0.3.0"
  def count_by_category_and_severity(binary_result) when is_binary(binary_result) do
    df = from_binary(binary_result)

    if has_column?(df, "category") do
      group_by_category(df)
      |> Map.new(&extract_counts/1)
    else
      %{}
    end
  end

  defp extract_counts({category, %{counts: counts}}) do
    {category, counts}
  end
end
